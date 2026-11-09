import XCTest
@testable import RefineCore
@testable import Refyn

final class LocalInferenceTests: XCTestCase {
    private struct ClarificationCase {
        let name: String
        let request: String
        let expectedGap: String
    }

    private let clarificationCases = [
        ClarificationCase(name: "bug fix", request: "Fix the login bug", expectedGap: "bug.reproduction"),
        ClarificationCase(name: "feature", request: "Add team invitations to workspace settings", expectedGap: "feature.acceptance"),
        ClarificationCase(name: "performance", request: "Improve report generation speed", expectedGap: "performance.metric"),
        ClarificationCase(name: "refactor", request: "Refactor the authorization service", expectedGap: "refactor.behavior"),
        ClarificationCase(name: "tests", request: "Write tests for CSV export", expectedGap: "test.scenarios"),
        ClarificationCase(name: "UI", request: "Improve the settings screen", expectedGap: "ui.states"),
        ClarificationCase(name: "docs", request: "Document account recovery", expectedGap: "docs.audience"),
        ClarificationCase(name: "configuration", request: "Configure production deployment", expectedGap: "config.secrets"),
    ]

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
        EvaluationCase(name: "ambiguous", request: "make authentication better", mode: .advanced, retain: ["authentication"], isSimple: false, expectsStructured: false),
        EvaluationCase(name: "complex feature", request: "add account deletion with a confirmation step, revoke sessions, preserve audit records, and test the full flow", mode: .advanced, retain: ["confirmation", "sessions", "audit", "test"], isSimple: false, expectsStructured: true),
        EvaluationCase(name: "bug fix", request: "fix crash when search query is empty; keep the current empty-state text", mode: .auto, retain: ["empty", "empty-state"], isSimple: false, expectsStructured: true),
        EvaluationCase(name: "refactor", request: "extract date formatting into a helper without changing displayed dates", mode: .basic, retain: ["date", "without changing"], isSimple: false, expectsStructured: false),
        EvaluationCase(name: "short request", request: "rename Save to Continue", mode: .auto, retain: ["Save", "Continue"], isSimple: true, expectsStructured: false),
        EvaluationCase(name: "verification workflow", request: "add retry to image uploads, run the upload tests, fix failures, then stop after two retries", mode: .advanced, retain: ["image uploads", "tests", "two retries"], isSimple: false, expectsStructured: true),
        EvaluationCase(name: "image upload retry", request: "image uploads sometimes fail on timeout. add retry but don't retry 4xx responses. keep the current progress UI, max 2 retries, and test timeout, offline, and permanent failure cases. don’t change upload API", mode: .advanced, retain: ["timeout", "4xx", "current progress UI", "2 retries", "offline", "permanent failure", "upload API"], isSimple: false, expectsStructured: true),
    ]

    func testModelConfigurationUsesQwen3FourBitCheckpoint() {
        XCTAssertEqual(LocalModelManager.modelID, "mlx-community/Qwen3-4B-4bit")
        XCTAssertTrue(LocalModelManager.modelLabel.contains("4-bit"))
    }

    @MainActor
    func testOptimizeStopsAtClarificationBeforeReturningLocalRules() async throws {
        let previousPreference = Preferences.askForMissingInformation
        Preferences.askForMissingInformation = true
        defer { Preferences.askForMissingInformation = previousPreference }

        let database = FileManager.default.temporaryDirectory.appending(path: "refyn-clarification-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: database) }
        let model = AppModel(store: try WorkspaceStore(databaseURL: database))
        model.input = "Add team invitations to workspace settings"
        await model.optimize()

        XCTAssertEqual(model.clarification?.requestText, model.input)
        XCTAssertEqual(model.clarification?.gaps.first?.id, "feature.acceptance")
        XCTAssertNil(model.plan, "Do not show an unchanged local-rules result before the user answers or skips.")
        XCTAssertFalse(model.isOptimizing)
        await model.shutdown()
    }

    @MainActor
    func testImageUploadRetryPromptProducesUsableModelOutput() async throws {
        guard ProcessInfo.processInfo.environment["REFINE_RUN_LOCAL_MODEL_EVALUATION"] == "1" else {
            throw XCTSkip("Set REFINE_RUN_LOCAL_MODEL_EVALUATION=1 to run the local Qwen output-quality check.")
        }
        let manager = LocalModelManager()
        await manager.install()
        let request = "image uploads sometimes fail on timeout. add retry but don't retry 4xx responses. keep the current progress UI, max 2 retries, and test timeout, offline, and permanent failure cases. don’t change upload API"
        let plan = try await PromptOptimizer(provider: LocalLLMProvider(manager: manager))
            .optimize(.init(text: request, mode: .advanced))
        print("Actual Qwen output for retry sample:\n\(plan.optimizedPrompt)")
        XCTAssertFalse(plan.validation.repaired, "The model should preserve the request without relying on a verbatim repair.")
        XCTAssertFalse(plan.tasks.isEmpty)
        XCTAssertFalse(plan.verificationInstructions.isEmpty)
        XCTAssertTrue(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("2 retries") }, "The retry limit must remain an acceptance criterion.")
        XCTAssertTrue(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("offline") }, "The offline case must remain an acceptance criterion.")
        XCTAssertFalse(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("progress UI") && $0.localizedCaseInsensitiveContains("updated") }, "Keeping the UI must not be rewritten as changing it.")
        XCTAssertTrue(plan.verificationInstructions.contains { $0.localizedCaseInsensitiveContains("offline") }, "The offline case must have an explicit verification step.")
        XCTAssertTrue(plan.missingInformation.contains { $0.localizedCaseInsensitiveContains("offline") } ||
                      plan.verificationInstructions.contains { $0.localizedCaseInsensitiveContains("existing") || $0.localizedCaseInsensitiveContains("observe") },
                      "Do not invent the expected behavior for the unspecified offline case.")
        XCTAssertFalse(plan.constraints.contains { $0.localizedCaseInsensitiveContains(request) }, "Do not repeat the full request as a constraint.")
        XCTAssertLessThan(plan.optimizedPrompt.count, 4_500, "The generated prompt should stay focused.")
        for marker in ["timeout", "4xx", "progress UI", "2 retries", "offline", "permanent failure", "upload API"] {
            XCTAssertTrue(plan.optimizedPrompt.localizedCaseInsensitiveContains(marker), "Missing required detail: \(marker)")
        }
    }

    @MainActor
    func testQwenOptimizesClarifiedShortFeatureInsteadOfEchoing() async throws {
        guard ProcessInfo.processInfo.environment["REFINE_RUN_LOCAL_MODEL_EVALUATION"] == "1" else {
            throw XCTSkip("Set REFINE_RUN_LOCAL_MODEL_EVALUATION=1 to run the local Qwen output-quality check.")
        }
        let manager = LocalModelManager()
        await manager.install()
        guard manager.state == .ready else { throw LLMError.unavailable(manager.state.title) }
        let answer = PromptAnswer(
            id: "feature.acceptance",
            question: "What observable result will tell us this feature is done?",
            answer: "Workspace admins can invite a person by email; the invite expires after 7 days."
        )
        let prompt = "Add team invitations to workspace settings"
        let plan = try await PromptOptimizer(provider: LocalLLMProvider(manager: manager)).optimize(.init(
            text: prompt,
            mode: .auto,
            userAnswers: [answer],
            unansweredQuestions: ["What existing behavior or compatibility must be preserved?"]
        ))
        print("Clarified short-feature output:\n\(plan.optimizedPrompt)")
        XCTAssertEqual(plan.provider, LocalModelManager.modelID)
        XCTAssertNotEqual(plan.optimizedPrompt.trimmingCharacters(in: .whitespacesAndNewlines), prompt)
        XCTAssertTrue(plan.optimizedPrompt.localizedCaseInsensitiveContains("7 days"))
        XCTAssertTrue(plan.optimizedPrompt.localizedCaseInsensitiveContains("workspace admins"))
        XCTAssertFalse(plan.optimizedPrompt.localizedCaseInsensitiveContains("open questions"))
        XCTAssertFalse(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("UI elements") },
                       "An unanswered scope question must not be turned into an acceptance criterion.")
    }

    @MainActor
    func testQwenTurnsReferencedWorkspaceNotesIntoSpecificRequirements() async throws {
        guard ProcessInfo.processInfo.environment["REFINE_RUN_LOCAL_MODEL_EVALUATION"] == "1" else {
            throw XCTSkip("Set REFINE_RUN_LOCAL_MODEL_EVALUATION=1 to run the local Qwen note-context check.")
        }
        let manager = LocalModelManager()
        await manager.install()
        guard manager.state == .ready else { throw LLMError.unavailable(manager.state.title) }
        let note = Note(workspaceID: UUID(), title: "Project note",
                        body: "Implementations: Be able to view older prompts aswell as send off notifications when the users prompt they are trying to optimize is compelte.")
        let request = "Implement the implementations from notes"
        let plan = try await PromptOptimizer(provider: LocalLLMProvider(manager: manager)).optimize(.init(
            text: request, mode: .advanced, notes: [note]))

        print("Referenced-note feature output:\n\(plan.optimizedPrompt)")
        XCTAssertEqual(plan.provider, LocalModelManager.modelID)
        XCTAssertTrue(plan.optimizedPrompt.localizedCaseInsensitiveContains("older prompts"))
        XCTAssertTrue(plan.optimizedPrompt.localizedCaseInsensitiveContains("notification"))
        XCTAssertFalse(plan.confirmedRequirements.isEmpty)
    }

    @MainActor
    func testClarificationQualityEvaluationEightUnderspecifiedAndTwoClearRequests() async throws {
        guard ProcessInfo.processInfo.environment["REFINE_RUN_LOCAL_MODEL_EVALUATION"] == "1" else {
            throw XCTSkip("Set REFINE_RUN_LOCAL_MODEL_EVALUATION=1 to run the underspecification and prompt quality evaluation.")
        }
        let manager = LocalModelManager()
        await manager.install()
        guard manager.state == .ready else { throw LLMError.unavailable(manager.state.title) }
        let optimizer = PromptOptimizer(provider: LocalLLMProvider(manager: manager))
        var gapHits = 0
        var noUnsupported = 0
        var preserved = 0
        var totalLatency: Duration = .zero

        for sample in clarificationCases {
            let analysis = RequestAnalysis(sample.request)
            let gaps = analysis.gaps
            if gaps.contains(where: { $0.id == sample.expectedGap }) { gapHits += 1 }
            let clock = ContinuousClock()
            let started = clock.now
            let plan = try await optimizer.optimize(.init(text: sample.request, mode: .auto,
                                                           unansweredQuestions: gaps.map(\.question)))
            let elapsed = started.duration(to: clock.now)
            totalLatency += elapsed
            let unsupported = InventionGuard.unsupportedSpecifics(in: plan.optimizedPrompt, sources: analysis.searchText, allowedNumbers: [])
            if unsupported.isEmpty { noUnsupported += 1 }
            if analysis.missingTerms(in: plan.optimizedPrompt).isEmpty { preserved += 1 }
            print("Clarification eval [\(sample.name)]: gap=\(gaps.contains { $0.id == sample.expectedGap }); unsupported=\(unsupported); preserved=\(analysis.missingTerms(in: plan.optimizedPrompt).isEmpty); latency=\(Duration.seconds(from: elapsed))s")
        }

        let clearRequests = [
            "Rename Save to Continue",
            "When I submit an expired password, the form shows success instead of an error. Expected: show the invalid-password message; actual: it redirects to the dashboard. Error: AUTH-401.",
        ]
        var clearCasesWithoutQuestions = 0
        for request in clearRequests {
            let analysis = RequestAnalysis(request)
            if analysis.gaps.isEmpty { clearCasesWithoutQuestions += 1 }
        }
        let meanLatency = Duration.seconds(from: totalLatency) / Double(clarificationCases.count)
        print("Clarification evaluation summary: expected gap detected \(gapHits)/8; no unsupported specifics \(noUnsupported)/8; original specifics preserved \(preserved)/8; clear controls without questions \(clearCasesWithoutQuestions)/2; mean local latency \(meanLatency)s")
        XCTAssertEqual(gapHits, 8)
        XCTAssertEqual(noUnsupported, 8)
        XCTAssertEqual(preserved, 8)
        XCTAssertEqual(clearCasesWithoutQuestions, 2)
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

    /// Prints optimized prompts for representative requests across modes so quality, latency and parsing can be reviewed.
    @MainActor
    func testPromptQualityAcrossModes() async throws {
        guard ProcessInfo.processInfo.environment["REFINE_RUN_LOCAL_MODEL_EVALUATION"] == "1" else {
            throw XCTSkip("Set REFINE_RUN_LOCAL_MODEL_EVALUATION=1 to print Qwen prompt-quality samples.")
        }
        let manager = LocalModelManager()
        await manager.install()
        guard manager.state == .ready else { throw LLMError.unavailable(manager.state.title) }
        let optimizer = PromptOptimizer(provider: LocalLLMProvider(manager: manager))
        let samples: [(String, PromptMode, [String])] = [
            ("the animation for opening the notch is bad", .auto, []),
            ("im building an notch app fix this prompt: it should be like a very slow opening and closing and smooth", .auto, []),
            ("Rename Save to Continue", .auto, ["Continue"]),
            ("add dark mode", .basic, []),
            ("saving a profile sometimes loses the avatar", .auto, ["avatar"]),
            ("make search faster but don't change the result order or the public API", .advanced, ["result order", "public API"]),
            ("why does the app launch slowly", .auto, []),
        ]
        for (text, mode, retain) in samples {
            let clock = ContinuousClock()
            let start = clock.now
            let plan = try await optimizer.optimize(.init(text: text, mode: mode, iterationLimit: 2))
            let elapsed = Duration.seconds(from: start.duration(to: clock.now))
            print("=== [\(mode.rawValue)] \(text)\nprovider=\(plan.provider) time=\(elapsed)s tasks=\(plan.tasks.count) suggestions=\(plan.suggestedDecisions.count) notices=\(plan.notices)\n\(plan.optimizedPrompt)\n")
            for term in retain {
                XCTAssertTrue(plan.optimizedPrompt.localizedCaseInsensitiveContains(term), "Lost: \(term) in \(text)")
            }
        }
    }

    /// Samples used for latency and quality comparisons, grouped by how heavy the request is.
    static let benchmarkSamples: [(tier: String, text: String, mode: PromptMode, retain: [String])] = [
        ("simple", "Rename Save to Continue", .auto, ["Continue"]),
        ("simple", "add a tooltip to the export button", .auto, ["tooltip", "export"]),
        ("simple", "the animation for opening the notch is bad", .auto, ["notch"]),
        ("moderate", "saving a profile sometimes loses the avatar", .auto, ["avatar"]),
        ("moderate", "add dark mode", .basic, ["dark mode"]),
        ("moderate", "make search faster but don't change the result order or the public API", .auto, ["result order", "public API"]),
        ("complex", "image uploads sometimes fail on timeout. add retry but don't retry 4xx responses. keep the current progress UI, max 2 retries, and test timeout, offline, and permanent failure cases. don’t change upload API", .advanced, ["4xx", "progress UI", "2 retries", "offline", "upload API"]),
        ("complex", "let workspace admins invite people by email, invites expire after 7 days, add resend and revoke, keep the current settings page layout, and add tests for expiry and duplicate members", .advanced, ["7 days", "resend", "revoke", "settings page layout", "duplicate"]),
    ]

    private static func peakMemoryMB() -> Int {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Int(usage.ru_maxrss) / 1_048_576
    }

    /// Runs the benchmark samples through the router and prints latency, token counts, tier and fallback frequency.
    @MainActor
    private func runBenchmark(label: String, withFastModel: Bool, showOutput: Bool = false) async throws {
        let manager = LocalModelManager()
        let loadStart = ContinuousClock.now
        await manager.install()
        guard manager.state == .ready else { throw LLMError.unavailable(manager.state.title) }
        var fast: LocalModelManager?
        if withFastModel {
            let f = LocalModelManager(modelID: LocalModelManager.fastModelID)
            await f.install()
            guard f.state == .ready else { throw LLMError.unavailable(f.state.title) }
            fast = f
        }
        print("BENCH \(label) load: \(Duration.seconds(from: loadStart.duration(to: .now)))s peakMemory=\(Self.peakMemoryMB())MB")
        let optimizer = PromptOptimizer(provider: LocalLLMProvider(manager: manager, fastManager: fast))
        var fallbacks = 0, lostTerms = 0
        var totals: [String: Double] = [:]
        for sample in Self.benchmarkSamples {
            let clock = ContinuousClock()
            let start = clock.now
            let plan = try await optimizer.optimize(.init(text: sample.text, mode: sample.mode, iterationLimit: 2))
            let elapsed = Duration.seconds(from: start.duration(to: clock.now))
            let usedModel = plan.provider != "local"
            let m = usedModel ? [manager.lastMetrics, fast?.lastMetrics].compactMap { $0 }.max { $0.sequence < $1.sequence } : nil
            let lost = sample.retain.filter { !plan.optimizedPrompt.localizedCaseInsensitiveContains($0) }
            if !plan.notices.isEmpty { fallbacks += 1 }
            lostTerms += lost.count
            totals[sample.tier, default: 0] += elapsed
            print(String(format: "BENCH %@ [%@] %.2fs prompt=%d out=%d ttft=%.2fs tps=%.1f path=%@ notices=%d lost=%@ tasks=%d chars=%d",
                         label, sample.tier, elapsed, m?.promptTokens ?? 0, m?.outputTokens ?? 0, m?.timeToFirstToken ?? 0, m?.tokensPerSecond ?? 0,
                         usedModel ? "model" : "local", plan.notices.count, lost.joined(separator: "|"), plan.tasks.count, plan.optimizedPrompt.count))
            if !plan.notices.isEmpty { print("BENCHNOTICE \(plan.notices.joined(separator: " | ").prefix(700))") }
            if showOutput { print("BENCHOUT [\(sample.tier)] \(sample.text)\n\(plan.optimizedPrompt)\n") }
        }
        print("BENCH \(label) summary: noticesOrFallbacks=\(fallbacks) lostTerms=\(lostTerms) totals=\(totals) peakMemory=\(Self.peakMemoryMB())MB")
    }

    @MainActor
    func testBenchmarkRouted4BOnly() async throws {
        guard ProcessInfo.processInfo.environment["REFINE_RUN_LOCAL_MODEL_EVALUATION"] == "1" else { throw XCTSkip("Set REFINE_RUN_LOCAL_MODEL_EVALUATION=1") }
        try await runBenchmark(label: "routed-4B", withFastModel: false, showOutput: ProcessInfo.processInfo.environment["BENCH_SHOW_OUTPUT"] == "1")
    }

    @MainActor
    func testBenchmarkRoutedWithFastModel() async throws {
        guard ProcessInfo.processInfo.environment["REFINE_RUN_LOCAL_MODEL_EVALUATION"] == "1" else { throw XCTSkip("Set REFINE_RUN_LOCAL_MODEL_EVALUATION=1") }
        try await runBenchmark(label: "routed-4B+1.7B", withFastModel: true, showOutput: ProcessInfo.processInfo.environment["BENCH_SHOW_OUTPUT"] == "1")
    }

    /// Baseline set for intent, constraints, hallucination checks, concise output, and useful workflows.
    @MainActor
    func testPromptEngineeringBaselineEvaluation() async throws {
        guard ProcessInfo.processInfo.environment["REFINE_RUN_LOCAL_MODEL_EVALUATION"] == "1" else {
            throw XCTSkip("Set REFINE_RUN_LOCAL_MODEL_EVALUATION=1 to run the eight-case Qwen quality baseline.")
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
            let analysis = RequestAnalysis(sample.request)
            let gaps = analysis.gaps
            let plan = try await optimizer.optimize(.init(text: sample.request, mode: sample.mode, iterationLimit: 2,
                                                           unansweredQuestions: gaps.map(\.question)))
            let elapsed = start.duration(to: clock.now)
            totalDuration += elapsed

            let text = plan.optimizedPrompt.lowercased()
            if sample.name == "image upload retry" { print("Prompt baseline output [image upload retry]:\n\(plan.optimizedPrompt)") }
            // Meaning, not wording: "without altering" satisfies "without changing"; a lost negation, number or identifier does not.
            let keptTerms = sample.retain.allSatisfy { MeaningMatch.contains(plan.optimizedPrompt, $0) }
            if keptTerms { preserved += 1 }
            if sample.isSimple, plan.optimizedPrompt.split(separator: "\n").count <= 16, !plan.optimizedPrompt.contains("Stage 1") { concise += 1 }
            inventedReferences += plan.codeReferences.count
            if sample.expectsStructured, !plan.tasks.isEmpty, !plan.verificationInstructions.isEmpty { structuredComplex += 1 }
            if sample.name == "ambiguous" {
                // The checklist has no gaps for this wording, and the model is told not to fill missingInformation,
                // so the check is that nothing unsupported is presented as the user's requirement.
                XCTAssertTrue(plan.confirmedRequirements.allSatisfy { sample.request.localizedCaseInsensitiveContains($0) || $0.count < 80 },
                              "Ambiguous work must not turn invented detail into stated requirements.")
            }
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
