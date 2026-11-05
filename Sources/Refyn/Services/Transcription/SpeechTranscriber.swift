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

/// Local speech-to-text with WhisperKit. Audio never leaves the Mac. Models are downloaded only
/// when the user asks, into Application Support/Refyn/SpeechModels.
actor SpeechTranscriber {
    private var kit: WhisperKit?
    private var loadedModel: String?

    static func modelFolder(_ model: SpeechModel) -> URL? {
        let root = AppPaths.speechModelsDirectory
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == model.rawValue {
            if FileManager.default.fileExists(atPath: url.appending(path: "AudioEncoder.mlmodelc").path) { return url }
        }
        return nil
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
