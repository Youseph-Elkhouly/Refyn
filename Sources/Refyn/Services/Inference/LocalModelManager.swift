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
    private var generationTask: Task<String, Error>?

    private var modelCacheBase: URL {
        AppPaths.supportDirectory.appending(path: "Models", directoryHint: .isDirectory)
    }

    private var modelRepository: URL {
        modelCacheBase.appending(path: "models/\(Self.modelID)", directoryHint: .isDirectory)
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
                    configuration: ModelConfiguration(id: Self.modelID)
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
            try await LLMModelFactory.shared.loadContainer(hub: hub, configuration: ModelConfiguration(id: Self.modelID))
        }
        loadTask = task
        defer { loadTask = nil }
        container = try await task.value
    }

    func generate(_ prompt: String) async throws -> String {
        if container == nil, isInstalled {
            do {
                try await ensureLoaded()
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
            let session = ChatSession(container, generateParameters: GenerateParameters(maxTokens: 1600, maxKVSize: 4096, temperature: 0.2, topP: 0.9))
            let task = Task<String, Error> {
                var result = ""
                var detector = JSONObjectEndDetector()
                for try await chunk in session.streamResponse(to: prompt) {
                    try Task.checkCancellation()
                    result += chunk
                    if detector.feed(chunk) { break }
                }
                return result
            }
            generationTask = task
            defer { generationTask = nil }
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch is CancellationError {
            throw LLMError.cancelled
        } catch {
            throw LLMError.unavailable(error.localizedDescription)
        }
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
    var identifier: String { LocalModelManager.modelID }

    func plan(for request: OptimizationRequest) async throws -> ModelPlan {
        let output = try await manager.generate(request.modelPrompt)
        guard let json = ModelOutput.jsonObject(from: output) else {
            throw LLMError.invalidResponse("No JSON object was returned.")
        }
        do {
            return try JSONDecoder().decode(ModelPlan.self, from: Data(json.utf8))
        } catch {
            let excerpt = String(json.prefix(900))
            throw LLMError.invalidResponse("\(error.localizedDescription) Response excerpt: \(excerpt)")
        }
    }
}
