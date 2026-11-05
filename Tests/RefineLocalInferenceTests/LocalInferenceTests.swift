import XCTest
import RefineCore
@testable import Refine

final class LocalInferenceTests: XCTestCase {
    func testModelConfigurationUsesQwen3FourBitCheckpoint() {
        XCTAssertEqual(LocalModelManager.modelID, "mlx-community/Qwen3-4B-4bit")
        XCTAssertTrue(LocalModelManager.modelLabel.contains("4-bit"))
    }

    /// Opt in explicitly because this downloads roughly 2.3 GB on first run and performs real inference.
    @MainActor
    func testDownloadAndRunModelThenRunOffline() async throws {
        guard ProcessInfo.processInfo.environment["REFINE_RUN_LOCAL_MODEL_INTEGRATION"] == "1" else {
            throw XCTSkip("Set REFINE_RUN_LOCAL_MODEL_INTEGRATION=1 to download Qwen3 and run the on-device integration test.")
        }

        let manager = LocalModelManager()
        let clock = ContinuousClock()
        let coldStart = clock.now
        await manager.install()
        guard manager.state == .ready else {
            XCTFail("Model download/load failed: \(manager.state.title)")
            return
        }
        let coldDuration = coldStart.duration(to: clock.now)

        let request = OptimizationRequest(
            analysis: RequestAnalysis("Fix the parser crash for empty input and keep ParserService.swift unchanged outside the parser."),
            mode: .advanced,
            techniques: [.decomposition, .constraints, .verification, .boundedIteration],
            context: RetrievedContext(workspaceName: "Fixture", languages: ["Swift"], frameworks: [], components: [], notes: [], analyzed: true),
            iterationLimit: 2
        )
        let provider = LocalLLMProvider(manager: manager)
        let warmStart = clock.now
        let first = try await provider.plan(for: request)
        let warmDuration = warmStart.duration(to: clock.now)
        XCTAssertFalse(first.objective.isEmpty)
        XCTAssertTrue(first.constraints.contains { $0.localizedCaseInsensitiveContains("ParserService.swift") } ||
                      first.confirmedRequirements.contains { $0.localizedCaseInsensitiveContains("ParserService.swift") })

        manager.unload()
        let offlineStart = clock.now
        let second = try await provider.plan(for: request)
        let offlineDuration = offlineStart.duration(to: clock.now)
        XCTAssertFalse(second.objective.isEmpty)
        print("Qwen3 local inference timings: load+download=\(coldDuration), warm=\(warmDuration), reloaded offline=\(offlineDuration)")
    }
}
