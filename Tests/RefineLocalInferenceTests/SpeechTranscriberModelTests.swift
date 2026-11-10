import Foundation
import XCTest
@testable import Refyn

final class SpeechTranscriberModelTests: XCTestCase {
    func testBundledSpeechModelIsFoundWhenItIsNotInApplicationSupport() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appending(path: "ApplicationSupport", directoryHint: .isDirectory)
        let resources = root.appending(path: "Resources/SpeechModels", directoryHint: .isDirectory)
        let bundledModel = resources.appending(path: SpeechModel.base.rawValue, directoryHint: .isDirectory)
        let encoder = bundledModel.appending(path: "AudioEncoder.mlmodelc", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: encoder, withIntermediateDirectories: true)

        let found = SpeechTranscriber.modelFolder(
            model: .base,
            supportDirectory: support,
            bundledResourceDirectory: resources
        )

        XCTAssertEqual(found?.standardizedFileURL, bundledModel.standardizedFileURL)
    }

    func testUserDownloadedSpeechModelTakesPrecedenceOverBundledCopy() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appending(path: "ApplicationSupport/SpeechModels", directoryHint: .isDirectory)
        let resources = root.appending(path: "Resources/SpeechModels", directoryHint: .isDirectory)
        let downloadedModel = support.appending(path: "models/vendor/\(SpeechModel.base.rawValue)", directoryHint: .isDirectory)
        let bundledModel = resources.appending(path: SpeechModel.base.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: downloadedModel.appending(path: "AudioEncoder.mlmodelc"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundledModel.appending(path: "AudioEncoder.mlmodelc"), withIntermediateDirectories: true)

        let found = SpeechTranscriber.modelFolder(
            model: .base,
            supportDirectory: support,
            bundledResourceDirectory: resources
        )

        XCTAssertEqual(found?.standardizedFileURL, downloadedModel.standardizedFileURL)
    }

    func testInstalledBaseModelLoadsAndTranscribesWithoutDownloading() async throws {
        guard SpeechTranscriber.isDownloaded(.base) else {
            throw XCTSkip("Set REFINE_SUPPORT_DIR to a folder containing SpeechModels/openai_whisper-base.en to run the offline model smoke test.")
        }

        let transcriber = SpeechTranscriber()
        let transcript = try await transcriber.transcribe(Array(repeating: 0, count: 16_000), model: .base)
        XCTAssertFalse(transcript.contains("[BLANK_AUDIO]"))
    }
}
