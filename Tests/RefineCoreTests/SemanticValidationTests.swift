import XCTest
@testable import RefineCore

/// Regression tests for the image-upload request that exposed intent, classification and context failures,
/// plus requests from other domains to show the checks are general.
final class SemanticValidationTests: XCTestCase {
    static let request = "image uploads sometimes fail on timeout. add retry but don't retry 4xx responses. keep the current progress UI, max 2 retries, and test timeout, offline, and permanent failure cases. don't change upload API."

    /// A workspace with unrelated features next to the one the request is about.
    static func graph() throws -> CodebaseGraph {
        try Fixtures.graph(nodes: [
            GraphNode(id: "mod:src/upload", name: "src/upload", type: .service, path: "src/upload", group: "Services", files: ["src/upload/ImageUploader.ts"],
                      symbols: [GraphSymbol(name: "uploadImage", kind: "function", path: "src/upload/ImageUploader.ts", line: 4)]),
            GraphNode(id: "mod:src/audio", name: "src/audio", type: .service, path: "src/audio", group: "Services", files: ["src/audio/Recorder.ts", "src/audio/SpeechRecognizer.ts"],
                      symbols: [GraphSymbol(name: "transcribeAudio", kind: "function", path: "src/audio/SpeechRecognizer.ts", line: 9)]),
            GraphNode(id: "mod:src/history", name: "src/history", type: .service, path: "src/history", group: "Services", files: ["src/history/PromptHistory.ts"],
                      symbols: [GraphSymbol(name: "savePromptHistory", kind: "function", path: "src/history/PromptHistory.ts", line: 2)]),
        ], edges: [])
    }

    static let notes = [Note(workspaceID: UUID(), title: "Speech", body: "Dictation uses a local recognizer."),
                        Note(workspaceID: UUID(), title: "History", body: "Prompt history keeps 50 entries.")]

    /// What a weak model produces: it narrows the retry rule, invents UI, prescribes offline behavior and cites unrelated files.
    static func flawedModelPlan() -> ModelPlan {
        ModelPlan(
            intent: "Add retry", taskType: "bugfix", role: "", objective: "Add retry logic to image uploads that retries only on HTTP 5xx responses.",
            confirmedRequirements: ["Retry only on 5xx responses", "Display retry attempts in the progress UI", "Add retry for image uploads",
                                    "keep the current progress UI", "add retry but don't retry 4xx responses", "don't change upload API"],
            suggestedDecisions: ["Show a retry counter in the progress UI", "Use exponential backoff between attempts"],
            constraints: ["Do not retry 4xx responses"],
            tasks: [.init(id: "t1", title: "Add a retry wrapper around the upload call", detail: "Retry up to 3 times."),
                    .init(id: "t2", title: "Show the retry count in the progress UI", detail: "", dependsOn: ["t1"]),
                    .init(id: "t3", title: "Add tests", detail: "Cover each case.", dependsOn: ["t1"])],
            successCriteria: ["Progress UI reflects retry attempts", "Uploads retry only on 5xx responses", "Offline uploads are automatically retried when the network returns", "Uploads retry up to 3 times"],
            verificationSteps: ["Run the existing tests"],
            codeReferences: [.init(path: "src/upload/ImageUploader.ts", symbol: "uploadImage", reason: "uploads images"),
                             .init(path: "src/audio/SpeechRecognizer.ts", reason: "handles retries")])
    }

    func optimize(_ text: String = request, plan: ModelPlan = flawedModelPlan(), mode: PromptMode = .advanced) async throws -> PromptPlan {
        try await PromptOptimizer(provider: StubProvider(result: .success(plan)))
            .optimize(.init(text: text, mode: mode, graph: try Self.graph(), notes: Self.notes))
    }

    // MARK: Image upload request

    func testRetryPolicyIsNotNarrowedToServerErrors() async throws {
        let plan = try await optimize()
        let prompt = plan.optimizedPrompt
        XCTAssertFalse(prompt.contains("5xx"), "the request never mentioned 5xx")
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("retry only"))
        XCTAssertTrue(prompt.contains("A failure caused by timeout triggers the requested retry behavior"), "timeouts are the problem being fixed")
        XCTAssertTrue(plan.constraints.contains { $0.localizedCaseInsensitiveContains("don't retry 4xx") || $0.localizedCaseInsensitiveContains("do not retry 4xx") })
        XCTAssertTrue(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("retry 4xx") }, "an observable criterion covers the 4xx prohibition")
    }

    func testTwoRetriesMeansThreeAttemptsInTotal() async throws {
        let plan = try await optimize()
        XCTAssertTrue(plan.successCriteria.contains("At most 2 retries follow the initial attempt, so at most 3 attempts in total."))
        XCTAssertFalse(plan.optimizedPrompt.contains("up to 3 times"), "a count that contradicts the limit is removed")
    }

    func testProgressUIAndUploadAPIArePreservedNotExtended() async throws {
        let plan = try await optimize()
        let prompt = plan.optimizedPrompt
        for invented in ["Display retry attempts", "retry counter", "retry count"] {
            XCTAssertFalse(prompt.localizedCaseInsensitiveContains(invented), invented)
        }
        XCTAssertTrue(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("preserve the current progress UI") }, "Keep the UI boundary without inventing UI/API behavior: \(plan.successCriteria)")
        XCTAssertTrue(plan.successCriteria.contains { $0.contains("upload API keeps its existing signature and behavior") })
        XCTAssertTrue(plan.tasks.allSatisfy { !$0.title.contains("progress UI") })
        XCTAssertTrue(plan.notices.contains { $0.contains("conflicted with the request") })
    }

    func testEveryRequestedScenarioIsTestedAndUnstatedOutcomesAreObserved() async throws {
        let plan = try await optimize()
        let steps = plan.verificationInstructions
        XCTAssertTrue(steps.contains { $0.hasPrefix("Test the timeout case against") }, "timeout behavior is described by the request")
        let offline = try XCTUnwrap(steps.first { $0.contains("offline case") })
        let permanent = try XCTUnwrap(steps.first { $0.contains("permanent failure case") })
        for step in [offline, permanent] { XCTAssertTrue(step.contains("report the observed behavior") && step.contains("do not invent")) }
        XCTAssertFalse(plan.optimizedPrompt.contains("automatically retried"), "no retry policy is invented for offline")
    }

    func testUnrelatedWorkspaceContextIsLeftOut() async throws {
        let plan = try await optimize()
        let prompt = plan.optimizedPrompt
        for unrelated in ["audio", "Speech", "PromptHistory", "Prompt history", "Express", "TypeScript", "Dictation"] {
            XCTAssertFalse(prompt.localizedCaseInsensitiveContains(unrelated), "\(unrelated) is not about image uploads")
        }
    }

    func testWorkspaceNoteNeedsMoreThanOneBroadWordToMatch() {
        let request = "Database operations are slow and time out under concurrent users; preserve the existing API and functionality."
        let note = Note(workspaceID: UUID(), title: "Prompt history", body: "Send completion notifications when users optimize a prompt.")
        let context = ContextRetriever.retrieve(for: RequestAnalysis(request), workspaceName: "w", graph: nil, notes: [note])
        XCTAssertTrue(context.notes.isEmpty, "The shared word 'users' does not make prompt-history notes relevant to database performance.")

        let databaseNote = Note(workspaceID: UUID(), title: "Database connection pool", body: "Pool wait time is recorded.")
        let related = ContextRetriever.retrieve(for: RequestAnalysis("Database requests time out while the connection pool is busy."), workspaceName: "w", graph: nil, notes: [databaseNote])
        XCTAssertEqual(related.notes.count, 1, "Multiple specific matches preserve relevant project context.")
    }

    func testConstraintOnlyTextCannotBeLabeledAsObservedBehavior() {
        let request = "The database is slow under concurrent users; fix it without changing the API or breaking anything."
        let analysis = RequestAnalysis(request)
        let directives = SemanticValidator.directives(in: request)
        XCTAssertTrue(directives.contains { $0.kind == .preserve && $0.objectText.localizedCaseInsensitiveContains("API") }, "the API is a preserved boundary: \(directives)")
        XCTAssertTrue(directives.contains { $0.kind == .prohibit && $0.verb == "break" && $0.objectText == "existing behavior" }, "generic 'anything' is not an observed symptom: \(directives)")
        XCTAssertFalse(analysis.constraints.contains { $0.localizedCaseInsensitiveContains("breaking anything") })
        XCTAssertFalse(SemanticValidator.clauses(request).contains { clause in
            !SemanticValidator.parse(clause).isEmpty && clause.localizedCaseInsensitiveContains("reported behavior")
        })
    }

    func testFileReferencesAreOnlyLeadsAndUnsupportedOnesAreDropped() async throws {
        let plan = try await optimize()
        XCTAssertFalse(plan.optimizedPrompt.contains("SpeechRecognizer"))
        XCTAssertTrue(plan.optimizedPrompt.contains("src/upload/ImageUploader.ts"))
        // A symbol in the code graph that matches the request is stronger evidence than a file name and is labelled as such.
        XCTAssertTrue(plan.optimizedPrompt.contains("Found in the code graph"))
        XCTAssertTrue(plan.optimizedPrompt.contains("symbol `uploadImage`"))
        XCTAssertFalse(plan.optimizedPrompt.contains("matched by name only"), "nothing here is a name-only match")
    }

    func testFileMatchedOnlyByNameIsAnInvestigationTarget() async throws {
        let graph = try Fixtures.graph(nodes: [GraphNode(id: "mod:src/upload", name: "src/upload", type: .service, path: "src/upload", group: "Services", files: ["src/upload/ImageUploader.ts"])], edges: [])
        var model = Self.flawedModelPlan(); model.codeReferences = [.init(path: "src/upload/ImageUploader.ts", reason: "upload code")]
        let plan = try await PromptOptimizer(provider: StubProvider(result: .success(model))).optimize(.init(text: Self.request, mode: .advanced, graph: graph))
        XCTAssertTrue(plan.optimizedPrompt.contains("Investigation targets (matched by name only"))
        XCTAssertFalse(plan.optimizedPrompt.contains("Found in the code graph"))
    }

    func testAFollowingInstructionIsNotSwallowedByAKeepClause() async throws {
        let request = "let workspace admins invite people by email, add resend and revoke, keep the current settings page layout, and add tests for expiry and duplicate members"
        let directives = SemanticValidator.directives(in: request)
        XCTAssertEqual(directives.map(\.objectText), ["the current settings page layout"], "only the layout is to be kept")
        var generated = ModelPlan(intent: "Invite by email", taskType: "feature", role: "", objective: "Let admins invite people by email")
        generated.tasks = [.init(id: "t1", title: "Add tests for expiry and duplicate members")]
        generated.successCriteria = ["Duplicate member checks pass all unit tests", "Resend and revoke work"]
        let (corrected, notices) = SemanticValidator.correct(generated, analysis: RequestAnalysis(request))
        XCTAssertEqual(corrected.tasks.count, 1)
        XCTAssertEqual(corrected.successCriteria.count, 2)
        XCTAssertTrue(notices.isEmpty)
    }

    func testRulesAreFiledAsConstraintsNotRequirements() async throws {
        let plan = try await optimize()
        XCTAssertTrue(plan.constraints.contains { $0.lowercased().contains("progress ui") })
        XCTAssertTrue(plan.constraints.contains { $0.lowercased().contains("upload api") })
        XCTAssertFalse(plan.confirmedRequirements.contains { $0.lowercased().contains("don't") || $0.lowercased().contains("keep the") }, "rules belong under Constraints")
        XCTAssertTrue(plan.confirmedRequirements.contains { $0.lowercased() == "add retry" }, "the plain request stays a requirement")
        XCTAssertFalse(plan.successCriteria.contains { $0.contains("reflects") }, "new behavior for the kept UI is removed")
    }

    func testAllOriginalConstraintsSurviveAsSeparateItems() async throws {
        let plan = try await optimize()
        let constraints = plan.constraints.joined(separator: "\n").lowercased()
        for expected in ["retry 4xx", "progress ui", "max 2 retries", "upload api"] { XCTAssertTrue(constraints.contains(expected), expected) }
    }

    func testCorrectlyBehavingModelOutputIsLeftAlone() throws {
        var good = Self.flawedModelPlan()
        good.objective = "Retry image uploads that fail on timeout, at most twice."
        good.confirmedRequirements = ["Add retry for image uploads"]
        good.suggestedDecisions = ["Use a short delay between attempts"]
        good.tasks = [.init(id: "t1", title: "Find the upload code"), .init(id: "t2", title: "Retry timeouts up to 2 times", dependsOn: ["t1"])]
        good.successCriteria = ["A timed-out upload is retried up to 2 times"]
        let (corrected, notices) = SemanticValidator.correct(good, analysis: RequestAnalysis(Self.request))
        XCTAssertEqual(corrected.tasks.count, 2)
        XCTAssertEqual(corrected.successCriteria, good.successCriteria)
        XCTAssertEqual(corrected.suggestedDecisions, good.suggestedDecisions)
        XCTAssertTrue(notices.isEmpty)
    }

    func testRetrievalKeepsOnlyUploadComponents() throws {
        let context = ContextRetriever.retrieve(for: RequestAnalysis(Self.request), workspaceName: "w", graph: try Self.graph(), notes: Self.notes)
        XCTAssertEqual(context.components.map(\.id), ["mod:src/upload"])
        XCTAssertTrue(context.notes.isEmpty)
        XCTAssertTrue(context.frameworks.isEmpty && context.languages.isEmpty, "the stack is not relevant unless the request names it")
    }

    func testWithoutAMatchingComponentTheAgentIsToldToLocateTheCode() async throws {
        var plan = Self.flawedModelPlan()
        plan.codeReferences = []
        let result = try await PromptOptimizer(provider: StubProvider(result: .success(plan)))
            .optimize(.init(text: Self.request, mode: .advanced, graph: try Fixtures.graph(nodes: [], edges: [])))
        XCTAssertTrue(result.tasks.first?.detail.localizedCaseInsensitiveContains("relevant code path") == true
                       || result.optimizedPrompt.localizedCaseInsensitiveContains("Locate the relevant implementation"))
        XCTAssertFalse(result.optimizedPrompt.contains("Investigation targets"))
    }

    // MARK: Other domains

    private func correct(_ request: String, removing bad: [String], keeping good: [String] = []) {
        var plan = ModelPlan(intent: "", taskType: "", role: "", objective: "", suggestedDecisions: bad + good)
        plan.successCriteria = bad
        let (corrected, notices) = SemanticValidator.correct(plan, analysis: RequestAnalysis(request))
        for item in bad {
            XCTAssertFalse(corrected.successCriteria.contains(item), "should remove: \(item)")
            XCTAssertFalse(corrected.suggestedDecisions.contains(item), "should remove: \(item)")
        }
        for item in good { XCTAssertTrue(corrected.suggestedDecisions.contains(item), "should keep: \(item)") }
        XCTAssertFalse(notices.isEmpty)
    }

    func testUIRequestKeepsExistingIcons() {
        correct("make the settings header feel cleaner but keep the existing icons and don't add new colors",
                removing: ["Replace the existing icons with outlined versions"], keeping: ["Use consistent spacing from one scale"])
    }

    func testAPIRefactorKeepsThePublicAPI() {
        correct("refactor the billing module to use async/await, don't change the public API, keep the existing tests passing",
                removing: ["Add an optional completion parameter to the public API"], keeping: ["Convert callbacks to async functions one at a time"])
    }

    func testAuthRequestForbidsPlainTextTokens() {
        correct("users get logged out after the token expires. fix it but never store tokens in plain text",
                removing: ["Store the refresh token in plain text for quick access"], keeping: ["Store the refresh token in the keychain"])
    }

    func testPerformanceRequestKeepsResultOrderAndAPI() {
        correct("make search faster but don't change the result order or the public API",
                removing: ["Change the public API to accept a page size"], keeping: ["Measure the current search time first"])
    }

    func testUIInterfaceConstraintIsNotRewrittenAsAnAPIContract() async throws {
        let request = "Make settings view opening faster without redesigning the interface."
        let model = ModelPlan(intent: "Improve settings view opening", taskType: "ui", role: "",
                              objective: "Make the settings view open faster without redesigning the interface.",
                              confirmedRequirements: ["Without redesigning the interface"],
                              tasks: [.init(id: "repro", title: "Measure settings view opening")],
                              successCriteria: ["The settings view opens quickly"],
                              verificationSteps: ["Repeat opening the settings view and record the elapsed time"])
        let plan = try await optimize(request, plan: model, mode: .advanced)
        XCTAssertFalse(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("signature and behavior") }, "UI constraints are not API contracts: \(plan.successCriteria)")
        XCTAssertTrue(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("current interface") }, "Keep the UI boundary grounded and readable: \(plan.successCriteria)")
    }

    func testBugFixDoesNotAlterTheSchema() {
        correct("saving a profile sometimes loses the avatar, don't change the profile schema",
                removing: ["Add a column to the profile schema for the avatar version"], keeping: ["Check the order of the upload and the save"])
    }

    func testAnOnlyRuleIsNotInventedFromAProhibition() {
        correct("add retry but don't retry 4xx responses. uploads fail on timeout",
                removing: ["Retry only on network errors"])
    }

    func testDefinitionsAppearOnlyForConceptsTheRequestUses() async throws {
        let plan = try await optimize("make search faster but don't change the result order or the public API", plan: ModelPlan(intent: "", taskType: "", role: "", objective: "Make search faster"))
        let terms = plan.terminology ?? []
        XCTAssertFalse(terms.contains { $0.hasPrefix("Latency") }, "Do not add a definition for a metric the user did not name.")
        XCTAssertFalse(terms.contains { $0.contains("timeout") || $0.contains("4xx") })
    }

    func testRequestsWithoutDirectivesAreUntouched() async throws {
        let plan = try await optimize("saving a profile sometimes loses the avatar", plan: ModelPlan(intent: "Keep the avatar", taskType: "", role: "", objective: "Keep the avatar when saving", tasks: [.init(id: "t1", title: "Reproduce the loss")], successCriteria: ["The avatar is kept after saving"]), mode: .auto)
        XCTAssertEqual(plan.successCriteria, ["The avatar is kept after saving"])
        XCTAssertTrue(plan.notices.allSatisfy { !$0.contains("conflicted") })
    }
}
