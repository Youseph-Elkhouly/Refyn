import Foundation
import Hub
import MLXLLM
import MLXLMCommon
import Observation
import RefineCore

@Observable
@MainActor
final class LocalModelManager {
    nonisolated static let modelID = "mlx-community/Qwen3-4B-4bit"
    nonisolated static let modelLabel = "Qwen3 4B · 4-bit"
    nonisolated static let fastModelID = "mlx-community/Qwen3-1.7B-4bit"

    /// What one generation cost. Token counts come from the tokenizer and the stream; times are wall clock.
    struct Metrics: Sendable {
        var promptTokens = 0
        var outputTokens = 0
        var timeToFirstToken: Double = 0
        var total: Double = 0
        /// Time spent loading the model for this request (0 when it was already in memory).
        var loadTime: Double = 0
        /// Increases with every generation across all managers, so the most recent can be told apart.
        var sequence = 0
        var tokensPerSecond: Double { total > timeToFirstToken ? Double(outputTokens) / (total - timeToFirstToken) : 0 }
    }

    let modelID: String

    init(modelID: String = LocalModelManager.modelID) { self.modelID = modelID }

    private(set) var lastMetrics: Metrics?
    private static var generationCounter = 0

    enum State: Equatable {
        case notInstalled
        case loading(progress: Double)
        case ready
        case generating
        case failed(String)

        var title: String {
            switch self {
            case .notInstalled: "Not downloaded"
            case .loading(let progress): "Downloading and loading · \(Int(progress * 100))%"
            case .ready: "Ready on this Mac"
            case .generating: "Generating locally"
            case .failed(let message): message
            }
        }
    }

    private(set) var state: State = .notInstalled
    private(set) var downloadProgress: Double?
    private var container: ModelContainer?
    private var operationTask: Task<Void, Never>?
    private var loadTask: Task<ModelContainer, Error>?
    private var generationTask: Task<(String, Metrics), Error>?

    private var modelCacheBase: URL {
        AppPaths.supportDirectory.appending(path: "Models", directoryHint: .isDirectory)
    }

    private var modelRepository: URL {
        modelCacheBase.appending(path: "models/\(modelID)", directoryHint: .isDirectory)
    }

    var isInstalled: Bool {
        guard FileManager.default.fileExists(atPath: modelRepository.appending(path: "config.json").path) else { return false }
        let enumerator = FileManager.default.enumerator(at: modelRepository, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "safetensors" { return true }
        }
        return false
    }

    func install() async {
        guard operationTask == nil else { return }
        downloadProgress = 0
        state = .loading(progress: 0)
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let hub = HubApi(downloadBase: self.modelCacheBase, useOfflineMode: self.isInstalled)
                let loaded = try await LLMModelFactory.shared.loadContainer(
                    hub: hub,
                    configuration: ModelConfiguration(id: modelID)
                ) { progress in
                    let fraction = min(1, max(0, progress.fractionCompleted.isFinite ? progress.fractionCompleted : 0))
                    Task { @MainActor [weak self] in
                        self?.downloadProgress = fraction
                        self?.state = .loading(progress: fraction)
                    }
                }
                try Task.checkCancellation()
                self.container = loaded
                self.downloadProgress = nil
                self.state = .ready
            } catch is CancellationError {
                self.downloadProgress = nil
                self.state = .notInstalled
            } catch {
                self.downloadProgress = nil
                self.state = .failed(error.localizedDescription)
            }
            self.operationTask = nil
        }
        await operationTask?.value
    }

    func cancel() {
        operationTask?.cancel()
        generationTask?.cancel()
    }

    /// Loads an installed model into memory ahead of the first request so it does not pay the load cost.
    func warmUp() async {
        guard container == nil, isInstalled, operationTask == nil else { return }
        _ = try? await ensureLoaded()
        if container != nil, state == .notInstalled { state = .ready }
    }

    private func ensureLoaded() async throws {
        if container != nil { return }
        if let loadTask { container = try await loadTask.value; return }
        let hub = HubApi(downloadBase: modelCacheBase, useOfflineMode: true)
        let task = Task<ModelContainer, Error> {
            try await LLMModelFactory.shared.loadContainer(hub: hub, configuration: ModelConfiguration(id: modelID))
        }
        loadTask = task
        defer { loadTask = nil }
        container = try await task.value
    }

    func generate(_ prompt: String, maxTokens: Int = 1600) async throws -> String {
        var loadTime = 0.0
        if container == nil, isInstalled {
            do {
                let started = ContinuousClock.now
                try await ensureLoaded()
                loadTime = Self.seconds(started.duration(to: .now))
            } catch {
                let message = "Saved model could not be loaded offline. Verify this Mac has enough unified memory (allow about 8 GB free) and download the model again. \(error.localizedDescription)"
                state = .failed(message)
                throw LLMError.unavailable(message)
            }
        }
        guard let container else { throw LLMError.modelNotInstalled }
        state = .generating
        defer { state = .ready }
        do {
            let session = ChatSession(container, generateParameters: GenerateParameters(maxTokens: maxTokens, maxKVSize: 4096, temperature: 0.2, topP: 0.9))
            let promptTokens = await container.perform { $0.tokenizer.encode(text: prompt).count }
            let task = Task<(String, Metrics), Error> {
                var result = ""
                var detector = JSONObjectEndDetector()
                var metrics = Metrics(promptTokens: promptTokens, loadTime: loadTime)
                let started = ContinuousClock.now
                for try await chunk in session.streamResponse(to: prompt) {
                    try Task.checkCancellation()
                    if metrics.outputTokens == 0 { metrics.timeToFirstToken = Self.seconds(started.duration(to: .now)) }
                    metrics.outputTokens += 1
                    result += chunk
                    if detector.feed(chunk) { break }
                }
                metrics.total = Self.seconds(started.duration(to: .now))
                return (result, metrics)
            }
            generationTask = task
            defer { generationTask = nil }
            let (text, metrics) = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            Self.generationCounter += 1
            var recorded = metrics
            recorded.sequence = Self.generationCounter
            lastMetrics = recorded
            return text
        } catch is CancellationError {
            throw LLMError.cancelled
        } catch {
            throw LLMError.unavailable(error.localizedDescription)
        }
    }

    nonisolated static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    func unload() {
        guard operationTask == nil, generationTask == nil else { return }
        container = nil
        state = .notInstalled
    }

    func removeDownloadedModel() throws {
        cancel()
        container = nil
        if FileManager.default.fileExists(atPath: modelRepository.path) {
            try FileManager.default.removeItem(at: modelRepository)
        }
        state = .notInstalled
    }
}

struct LocalLLMProvider: LLMProvider, @unchecked Sendable {
    let manager: LocalModelManager
    /// Optional small model for moderate requests. Used only when it is installed; otherwise the main model runs them.
    var fastManager: LocalModelManager?
    var identifier: String { LocalModelManager.modelID }

    func plan(for request: OptimizationRequest) async throws -> ModelPlan {
        var target = manager
        if request.tier == .moderate, let fastManager, await fastManager.isInstalled { target = fastManager }
        let output = try await target.generate(request.modelPrompt, maxTokens: request.tier.outputTokenBudget)
        guard let extraction = ModelOutput.extract(from: output) else {
            throw LLMError.invalidResponse("No recoverable JSON object was returned.")
        }
        let json = extraction.json
        do {
            var plan = try JSONDecoder().decode(ModelPlan.self, from: Data(json.utf8))
            plan.recoveryEdits = extraction.edits
            return plan
        } catch {
            let excerpt = json.count <= 700 ? json : String(json.prefix(300)) + " … " + String(json.suffix(380))
            throw LLMError.invalidResponse("\(error.localizedDescription) Response excerpt: \(excerpt)")
        }
    }
}
