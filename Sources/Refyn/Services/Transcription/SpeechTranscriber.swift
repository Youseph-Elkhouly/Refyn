import Foundation
import RefineCore
@preconcurrency import WhisperKit

enum SpeechModel: String, CaseIterable, Identifiable {
    case tiny = "openai_whisper-tiny.en"
    case base = "openai_whisper-base.en"
    case small = "openai_whisper-small.en"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tiny: "Tiny (English, ~75 MB, fastest)"
        case .base: "Base (English, ~145 MB)"
        case .small: "Small (English, ~480 MB, most accurate)"
        }
    }
}

enum TranscriberError: Error, LocalizedError {
    case modelNotDownloaded
    var errorDescription: String? { "Download a speech model in Settings › Voice before dictating." }
}

/// Local speech-to-text with WhisperKit. Audio never leaves the Mac. Optional models are downloaded
/// into Application Support/Refyn/SpeechModels; release builds can include the default model.
actor SpeechTranscriber {
    private var kit: WhisperKit?
    private var loadedModel: String?

    static func modelFolder(_ model: SpeechModel) -> URL? {
        modelFolder(
            model: model,
            supportDirectory: AppPaths.speechModelsDirectory,
            bundledResourceDirectory: Bundle.main.resourceURL?.appending(path: "SpeechModels", directoryHint: .isDirectory)
        )
    }

    static func modelFolder(model: SpeechModel, supportDirectory: URL, bundledResourceDirectory: URL?) -> URL? {
        let fileManager = FileManager.default
        let roots = [supportDirectory, bundledResourceDirectory].compactMap { $0 }

        for root in roots {
            let directModel = root.appending(path: model.rawValue, directoryHint: .isDirectory)
            if containsAudioEncoder(at: directModel, fileManager: fileManager) { return directModel }

            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator where url.lastPathComponent == model.rawValue {
                if containsAudioEncoder(at: url, fileManager: fileManager) { return url }
            }
        }
        return nil
    }

    static func isBundled(_ model: SpeechModel) -> Bool {
        guard let resourceRoot = Bundle.main.resourceURL?.appending(path: "SpeechModels", directoryHint: .isDirectory) else { return false }
        let folder = resourceRoot.appending(path: model.rawValue, directoryHint: .isDirectory)
        return containsAudioEncoder(at: folder, fileManager: .default)
    }

    private static func containsAudioEncoder(at folder: URL, fileManager: FileManager) -> Bool {
        fileManager.fileExists(atPath: folder.appending(path: "AudioEncoder.mlmodelc").path)
    }

    static func isDownloaded(_ model: SpeechModel) -> Bool { modelFolder(model) != nil }

    static func download(_ model: SpeechModel, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try FileManager.default.createDirectory(at: AppPaths.speechModelsDirectory, withIntermediateDirectories: true)
        return try await WhisperKit.download(variant: model.rawValue, downloadBase: AppPaths.speechModelsDirectory) { p in
            progress(p.fractionCompleted)
        }
    }

    func transcribe(_ samples: [Float], model: SpeechModel) async throws -> String {
        guard samples.count > 1_600 else { return "" } // under 0.1 s
        if kit == nil || loadedModel != model.rawValue {
            guard let folder = Self.modelFolder(model) else { throw TranscriberError.modelNotDownloaded }
            kit = try await WhisperKit(WhisperKitConfig(model: model.rawValue, modelFolder: folder.path, verbose: false, logLevel: .error, prewarm: true, load: true, download: false))
            loadedModel = model.rawValue
        }
        let results = try await kit!.transcribe(audioArray: samples)
        return results.map(\.text).joined(separator: " ")
            .replacingOccurrences(of: "\\[[A-Z_ ]+\\]|<\\|[^|]+\\|>", with: "", options: .regularExpression) // [BLANK_AUDIO], special tokens
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unload() { kit = nil; loadedModel = nil }
}
