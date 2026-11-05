import Foundation
import XCTest
@testable import RefineCore

final class AppPathsMigrationTests: XCTestCase {
    func testOldRefineDataMovesIntactToRefynSupportDirectory() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let old = base.appending(path: "Refine", directoryHint: .isDirectory)
        let database = old.appending(path: "refine.sqlite")
        let model = old.appending(path: "Models/Qwen/model.safetensors")
        try FileManager.default.createDirectory(at: model.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("existing workspace, notes, and prompts".utf8).write(to: database)
        try Data("local model weights".utf8).write(to: model)
        defer { try? FileManager.default.removeItem(at: base) }

        let destination = AppPaths.supportDirectory(at: base)
        XCTAssertEqual(destination.lastPathComponent, "Refyn")
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try Data(contentsOf: destination.appending(path: "refine.sqlite")), Data("existing workspace, notes, and prompts".utf8))
        XCTAssertEqual(try Data(contentsOf: destination.appending(path: "Models/Qwen/model.safetensors")), Data("local model weights".utf8))
    }
}
