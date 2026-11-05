import XCTest
import RefineCore
@testable import Refyn

final class LocalInferenceTests: XCTestCase {
    private struct EvaluationCase {
        let name: String
        let request: String
        let mode: PromptMode
        let retain: [String]
        let isSimple: Bool
        let expectsStructured: Bool
    }

    private let evaluationCases = [
        EvaluationCase(name: "rough feature", request: "add csv export to reports but keep current filters", mode: .auto, retain: ["csv", "filters"], isSimple: false, expectsStructured: false),
        EvaluationCase(name: "ambiguous", request: "make authentication better", mode: .advanced, retain: ["authentication"], isSimple: false, expectsStructured: true),
        EvaluationCase(name: "complex feature", request: "add account deletion with a confirmation step, revoke sessions, preserve audit records, and test the full flow", mode: .advanced, retain: ["confirmation", "sessions", "audit", "test"], isSimple: false, expectsStructured: true),
        EvaluationCase(name: "bug fix", request: "fix crash when search query is empty; keep the current empty-state text", mode: .auto, retain: ["empty", "empty-state"], isSimple: false, expectsStructured: true),
        EvaluationCase(name: "refactor", request: "extract date formatting into a helper without changing displayed dates", mode: .basic, retain: ["date", "without changing"], isSimple: false, expectsStructured: false),
        EvaluationCase(name: "short request", request: "rename Save to Continue", mode: .auto, retain: ["Save", "Continue"], isSimple: true, expectsStructured: false),
        EvaluationCase(name: "verification workflow", request: "add retry to image uploads, run the upload tests, fix failures, then stop after two retries", mode: .advanced, retain: ["image uploads", "tests", "two retries"], isSimple: false, expectsStructured: true),
    ]

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

    /// Baseline set for intent, constraints, hallucination checks, concise output, and useful workflows.
    @MainActor
    func testPromptEngineeringBaselineEvaluation() async throws {
        guard ProcessInfo.processInfo.environment["REFINE_RUN_LOCAL_MODEL_EVALUATION"] == "1" else {
            throw XCTSkip("Set REFINE_RUN_LOCAL_MODEL_EVALUATION=1 to run the seven-case Qwen quality baseline.")
        }

        let manager = LocalModelManager()
        await manager.install()
        guard manager.state == .ready else { throw LLMError.unavailable(manager.state.title) }
        let optimizer = PromptOptimizer(provider: LocalLLMProvider(manager: manager))
        var totalDuration: Duration = .zero
        var preserved = 0
        var concise = 0
        var inventedReferences = 0
        var structuredComplex = 0

        for sample in evaluationCases {
            let clock = ContinuousClock()
            let start = clock.now
            let plan = try await optimizer.optimize(.init(text: sample.request, mode: sample.mode, iterationLimit: 2))
            let elapsed = start.duration(to: clock.now)
            totalDuration += elapsed

            let text = plan.optimizedPrompt.lowercased()
            let keptTerms = sample.retain.allSatisfy { text.contains($0.lowercased()) }
            if keptTerms { preserved += 1 }
            if sample.isSimple, plan.optimizedPrompt.count <= max(120, sample.request.count * 3), !plan.optimizedPrompt.contains("##") { concise += 1 }
            inventedReferences += plan.codeReferences.count
            if sample.expectsStructured, !plan.tasks.isEmpty, !plan.verificationInstructions.isEmpty { structuredComplex += 1 }
            print("Prompt baseline [\(sample.name)]: \(Duration.seconds(from: elapsed))s; retained=\(keptTerms); tasks=\(plan.tasks.count); refs=\(plan.codeReferences.count); outputChars=\(plan.optimizedPrompt.count)")
        }

        XCTAssertEqual(preserved, evaluationCases.count, "Every explicit request marker must survive in the result or its verbatim repair.")
        XCTAssertEqual(concise, 1, "Auto should keep the simple rename prompt compact.")
        XCTAssertEqual(inventedReferences, 0, "No code references are valid when no workspace is selected.")
        let expectedStructured = evaluationCases.filter(\.expectsStructured).count
        XCTAssertEqual(structuredComplex, expectedStructured, "Advanced, complex, bug-fix, and verification requests should return ordered work and verification steps.")
        print("Prompt baseline summary: \(preserved)/\(evaluationCases.count) intent markers retained, \(concise)/1 concise, \(inventedReferences) unverified refs, \(structuredComplex)/\(expectedStructured) structured; total \(Duration.seconds(from: totalDuration))s")
    }
}

private extension Duration {
    static func seconds(from duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}
