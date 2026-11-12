import XCTest
@testable import RefineCore

final class PromptQualityTests: XCTestCase {
    struct Provider: LLMProvider {
        let identifier = "quality-test"
        func plan(for request: OptimizationRequest) async throws -> ModelPlan {
            ModelPlan(intent: request.analysis.intent, taskType: "bugfix", role: "", objective: request.analysis.intent,
                      tasks: [.init(id: "a", title: "Reproduce the intermittent failure", detail: "Record triggers and observed behavior."),
                              .init(id: "b", title: "Trace the failing path", detail: "Inspect the implementation before choosing a fix.", dependsOn: ["a"])],
                      successCriteria: ["Works properly.", "No new bugs or issues are introduced."],
                      verificationSteps: ["Replay the recorded reproduction and report actual results."])
        }
    }
    struct DatabaseProvider: LLMProvider {
        let identifier = "database-quality-test"
        func plan(for request: OptimizationRequest) async throws -> ModelPlan {
            ModelPlan(intent: "Fix database performance", taskType: "performance", role: "",
                      objective: "Make database operations faster and reliable under concurrent users without changing the API or breaking functionality.",
                      suggestedDecisions: [
                        "Investigate the reported behavior: without changing the API or breaking anything.",
                        "Profile slow database queries under concurrent load.",
                        "Rebuild database indexes.",
                      ],
                      constraints: ["Unchanged: breaking anything"],
                      tasks: [
                        .init(id: "logs", title: "Review database logs"),
                        .init(id: "queries", title: "Inspect database query plans", dependsOn: ["logs"]),
                        .init(id: "cpu", title: "Monitor CPU and memory", dependsOn: ["queries"]),
                        .init(id: "settings", title: "Check connection and transaction settings", detail: "Review and optimize connection pooling and transaction isolation levels", dependsOn: ["cpu"]),
                        .init(id: "index", title: "Add and rebuild database indexes", dependsOn: ["cpu"]),
                        .init(id: "verify", title: "Compare the same concurrent workload", dependsOn: ["index"]),
                      ],
                      successCriteria: ["The database is significantly faster", "No timeout occurs under concurrent load"],
                      verificationSteps: ["Profile query latency under the same concurrent workload", "Run the existing regression tests"])
        }
    }
    func testBasicRenderingRetainsUsefulModelStepsAndVerification() async throws {
        let plan = try await PromptOptimizer(provider: Provider()).optimize(.init(text: "my api keeps breaking sometimes", mode: .basic))
        XCTAssertTrue(plan.optimizedPrompt.contains("Trace the failing path"))
        XCTAssertTrue(plan.optimizedPrompt.contains("Replay the recorded reproduction"))
        XCTAssertFalse(plan.optimizedPrompt.contains("Works properly"))
        XCTAssertFalse(plan.optimizedPrompt.contains("No new bugs"))
        XCTAssertFalse(plan.optimizedPrompt.contains("Example report"))
    }
    func testVagueRequestGetsInvestigationWithoutInventedBugOrNumbers() async throws {
        let text = "the notch is kinda buggy and slow sometimes. opening and closing feels weird and some stuff doesnt work properly. test everything and fix whatever is wrong but dont mess up the design."
        let plan = try await PromptOptimizer(provider: Provider()).optimize(.init(text: text, mode: .auto))
        XCTAssertTrue(plan.optimizedPrompt.contains("rapid reversals"))
        XCTAssertTrue(plan.optimizedPrompt.contains("focus and lifecycle"))
        XCTAssertTrue(plan.optimizedPrompt.contains("Profile"))
        XCTAssertTrue(plan.optimizedPrompt.contains("manual observations"))
        XCTAssertFalse(plan.optimizedPrompt.contains("Confirmed by a test or inspection"))
        XCTAssertTrue(plan.constraints.contains { $0.contains("design") })
        XCTAssertTrue(plan.confirmedRequirements.allSatisfy { !$0.contains("focus") })
    }
    func testUnsupportedNumericalTargetIsRemovedWithoutLosingUserTarget() {
        let analysis = RequestAnalysis("make search faster")
        var plan = PromptPlan(originalPrompt: analysis.text, intent: analysis.intent, taskType: .performance,
                              successCriteria: ["Search completes under 20ms"], suggestedDecisions: ["Target 60fps"])
        PromptQuality.repair(&plan, analysis: analysis)
        XCTAssertFalse(plan.successCriteria.contains { $0.contains("20ms") })
        XCTAssertFalse(plan.suggestedDecisions.contains { $0.contains("60fps") })
        XCTAssertFalse(plan.successCriteria.isEmpty)
        var specified = PromptPlan(originalPrompt: "Search must complete under 20ms", intent: "Improve search", taskType: .performance,
                                   successCriteria: ["Search completes under 20ms"])
        PromptQuality.repair(&specified, analysis: RequestAnalysis(specified.originalPrompt))
        XCTAssertTrue(specified.successCriteria.contains { $0.contains("20ms") })
    }

    func testVagueImprovementDoesNotAuthorizeNewCapabilities() {
        let analysis = RequestAnalysis("make login more secure")
        var plan = PromptPlan(originalPrompt: analysis.text, intent: analysis.intent, taskType: analysis.taskType,
                              tasks: [.init(id: "a", title: "Integrate multi-factor authentication"),
                                      .init(id: "b", title: "Enforce HTTPS for login requests", dependsOn: ["a"]),
                                      .init(id: "c", title: "Encrypt login data")],
                              successCriteria: ["All sensitive data is encrypted"],
                              verificationInstructions: ["Verify encryption of all data"])
        PromptQuality.repair(&plan, analysis: analysis)
        XCTAssertFalse(plan.tasks.contains { $0.title.hasPrefix("Integrate") || $0.title.hasPrefix("Enforce") })
        // The remedies stay visible, but only as options that depend on what the investigation finds.
        XCTAssertTrue(plan.suggestedDecisions.contains { $0.hasPrefix("Possible causes or approaches") && $0.contains("multi-factor") })
        XCTAssertFalse(plan.successCriteria.contains { $0.contains("encrypted") })
        XCTAssertFalse(plan.tasks.contains { $0.title.contains("Encrypt") })
        XCTAssertFalse(plan.tasks.isEmpty)
        XCTAssertNotNil(PromptComposer.topologicalOrder(plan.tasks))
    }

    func testRenameRemainsSmallAndCustomRemainsOptIn() async throws {
        let small = try await PromptOptimizer(provider: nil).optimize(.init(text: "Rename Save to Continue", mode: .auto))
        XCTAssertFalse(small.optimizedPrompt.contains("Profile"))
        XCTAssertFalse(small.optimizedPrompt.contains("root cause"))
        let custom = try await PromptOptimizer(provider: Provider()).optimize(.init(text: "my api keeps breaking sometimes", mode: .custom, customTechniques: [.constraints]))
        XCTAssertFalse(custom.optimizedPrompt.contains("## Tasks"))
    }

    static let notch = "the notch is kinda buggy and slow sometimes. opening and closing feels weird and some stuff doesnt work properly. test everything and fix whatever is wrong but dont mess up the design."

    /// What Qwen3-4B actually returned for the notch request, trimmed: investigation tasks, "Implement fixes", and stock criteria.
    struct NotchProvider: LLMProvider {
        let identifier = "recorded-notch"
        func plan(for request: OptimizationRequest) async throws -> ModelPlan {
            ModelPlan(intent: "Fix the notch", taskType: "bugfix", role: "", objective: "Test and fix the notch's bugs and performance issues without altering its design.",
                      suggestedDecisions: ["Check for any error messages or logs"],
                      tasks: [.init(id: "t1", title: "Reproduce the issues", detail: "Test the notch to identify specific bugs."),
                              .init(id: "t2", title: "Investigate the cause", detail: "Analyze the code.", dependsOn: ["t1"]),
                              .init(id: "t3", title: "Implement fixes", detail: "Resolve the identified issues.", dependsOn: ["t2"]),
                              .init(id: "t4", title: "Add regression tests", detail: "", dependsOn: ["t3"])],
                      successCriteria: ["The notch runs smoothly without bugs", "All features function as expected", "The app's design remains unchanged"],
                      verificationSteps: ["Check that the design is unchanged after fixes"])
        }
    }

    func testNotchPlanKeepsTheFixAndGainsObservableCriteria() async throws {
        let plan = try await PromptOptimizer(provider: NotchProvider()).optimize(.init(text: Self.notch, mode: .auto))
        XCTAssertEqual(plan.tasks.first?.title, "Reproduce the issues")
        XCTAssertFalse(plan.tasks.first?.detail.localizedCaseInsensitiveContains("relevant code path") == true,
                       "A useful model-provided detail should not be prefixed with a generic template sentence.")
        XCTAssertTrue(plan.tasks.contains { $0.title == "Implement fixes" }, "the user asked for a fix: \(plan.tasks.map(\.title))")
        XCTAssertFalse(plan.optimizedPrompt.contains("Investigate whether this proposal"))
        for expected in ["Each transition completes", "design remains unchanged"] {
            XCTAssertTrue(plan.successCriteria.contains { $0.contains(expected) }, expected)
        }
        XCTAssertTrue(plan.verificationInstructions.contains { $0.contains("manual") })
        XCTAssertFalse(plan.successCriteria.contains { $0.contains("smoothly") || $0.contains("function as expected") })
        XCTAssertFalse(plan.successCriteria.contains(where: PromptQuality.genericCriterion), "\(plan.successCriteria)")
        XCTAssertTrue(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("opening and closing") || $0.localizedCaseInsensitiveContains("transition") })
        XCTAssertTrue(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("reported as not working") || $0.localizedCaseInsensitiveContains("not working") })
        XCTAssertLessThanOrEqual(plan.successCriteria.count, 7)
        XCTAssertTrue(plan.constraints.contains { $0.localizedCaseInsensitiveContains("mess up") && $0.localizedCaseInsensitiveContains("design") }, "\(plan.constraints)")
    }

    func testReportedFreezeAndUnresponsiveButtonsProduceObservableChecks() {
        let request = "the app is slow when opening windows and switching views. buttons sometimes dont respond and the UI freezes. fix it and dont change the design."
        let analysis = RequestAnalysis(request)
        var plan = PromptPlan(originalPrompt: request, intent: analysis.intent, taskType: .bugfix,
                              tasks: [.init(id: "inspect", title: "Reproduce the reported issue")],
                              successCriteria: ["Everything works properly."])

        PromptQuality.repair(&plan, analysis: analysis)

        let criteria = plan.successCriteria.joined(separator: " ").lowercased()
        XCTAssertTrue(criteria.contains("opening and closing") || criteria.contains("slow operation"), criteria)
        XCTAssertTrue(criteria.contains("button") && criteria.contains("respond"), criteria)
        XCTAssertTrue(criteria.contains("interface") && criteria.contains("interactive"), criteria)
        XCTAssertFalse(plan.successCriteria.contains(where: PromptQuality.genericCriterion), "\(plan.successCriteria)")
        XCTAssertTrue(plan.tasks.contains { ($0.title + " " + $0.detail).localizedCaseInsensitiveContains("UI freezes") || ($0.title + " " + $0.detail).localizedCaseInsensitiveContains("interface freezes") }, "The reported freeze must remain an investigation target: \(plan.tasks)")
    }

    func testAFixIsAddedWhenTheModelOnlyInvestigated() {
        let analysis = RequestAnalysis("the app is slow and buggy fix it")
        var plan = PromptPlan(originalPrompt: analysis.text, intent: analysis.intent, taskType: analysis.taskType,
                              tasks: [.init(id: "a", title: "Reproduce the slowdown"), .init(id: "b", title: "Profile the slow path"), .init(id: "c", title: "Run the existing tests")])
        PromptQuality.repair(&plan, analysis: analysis)
        XCTAssertEqual(plan.tasks.map(\.title).last(where: { $0.contains("Fix") }), "Fix confirmed issues")
        let fix = plan.tasks.firstIndex { $0.title == "Fix confirmed issues" }!, test = plan.tasks.firstIndex { $0.title == "Run the existing tests" }!
        XCTAssertLessThan(fix, test, "the fix comes before the check")
    }

    func testAConcreteRequestKeepsItsImplementationTasks() {
        let analysis = RequestAnalysis(SemanticValidationTests.request)
        var plan = PromptPlan(originalPrompt: analysis.text, intent: analysis.intent, taskType: analysis.taskType,
                              tasks: [.init(id: "a", title: "Locate the upload code"), .init(id: "b", title: "Implement exponential backoff between attempts", dependsOn: ["a"])],
                              successCriteria: ["4xx responses are not retried"], verificationInstructions: ["Run the existing tests"])
        PromptQuality.repair(&plan, analysis: analysis)
        XCTAssertTrue(plan.tasks.contains { $0.title.hasPrefix("Implement exponential backoff") }, "the user said what they want, so this is not a speculative remedy")
    }

    func testRefactorIsNotTreatedAsABugBecauseItSaysBreaking() {
        let analysis = RequestAnalysis("clean up this code without breaking anything")
        var plan = PromptPlan(originalPrompt: analysis.text, intent: analysis.intent, taskType: analysis.taskType,
                              tasks: [.init(id: "a", title: "Identify duplicated code"), .init(id: "b", title: "Refactor for clarity")],
                              successCriteria: ["Code is cleaner and more maintainable"], verificationInstructions: ["Run existing tests"])
        PromptQuality.repair(&plan, analysis: analysis)
        XCTAssertFalse(plan.verificationInstructions.contains { $0.contains("reproduced failure") })
        XCTAssertFalse(plan.successCriteria.contains { $0.contains("reported failure") || $0.contains("reproduction") }, "A refactor's 'without breaking' constraint is not a bug report.")
        XCTAssertFalse(plan.successCriteria.contains { $0.contains("cleaner") })
        XCTAssertTrue(plan.successCriteria.contains { $0.contains("same observable outputs") })
        XCTAssertEqual(SemanticValidator.directives(in: analysis.text).first?.objectText, "existing behavior")
    }

    func testVagueSecurityRequestGathersRemediesIntoOneConditionalLine() {
        let analysis = RequestAnalysis("make login more secure")
        var plan = PromptPlan(originalPrompt: analysis.text, intent: analysis.intent, taskType: analysis.taskType,
                              tasks: [.init(id: "a", title: "Validate and sanitize inputs", detail: "Update validation rules to prevent injection."),
                                      .init(id: "b", title: "Add rate limiting"), .init(id: "c", title: "Review the current login flow")],
                              suggestedDecisions: ["Implement rate limiting to prevent brute force attacks", "Check how sessions expire today"])
        PromptQuality.repair(&plan, analysis: analysis)
        XCTAssertFalse(plan.tasks.contains { $0.title.hasPrefix("Validate") || $0.title.hasPrefix("Add rate") })
        XCTAssertEqual(plan.tasks.first?.title, "Review the current login flow", "investigation comes first")
        let conditional = plan.suggestedDecisions.filter { $0.hasPrefix("Possible causes or approaches") }
        XCTAssertEqual(conditional.count, 1)
        XCTAssertEqual(conditional[0].components(separatedBy: "rate limiting").count - 1, 1, "the same remedy is listed once: \(conditional[0])")
        XCTAssertFalse(plan.suggestedDecisions.contains { $0.hasPrefix("Implement") })
        XCTAssertTrue(plan.suggestedDecisions.contains("Check how sessions expire today"))
    }

    func testRealTestCriteriaAreNotTreatedAsGeneric() {
        XCTAssertFalse(PromptQuality.genericCriterion("All existing tests pass without errors"))
        XCTAssertTrue(PromptQuality.genericCriterion("Everything is tested"))
        XCTAssertTrue(PromptQuality.genericCriterion("No new bugs or issues are introduced."))
    }

    func testRemovingATaskPreservesTheDependencyChain() {
        let analysis = RequestAnalysis("the app is slow and buggy fix it")
        var plan = PromptPlan(originalPrompt: analysis.text, intent: analysis.intent, taskType: analysis.taskType,
                              tasks: [.init(id: "a", title: "Reproduce the slowdown"),
                                      .init(id: "b", title: "Integrate a caching layer", dependsOn: ["a"]),
                                      .init(id: "c", title: "Run the existing tests", dependsOn: ["b"])])
        PromptQuality.repair(&plan, analysis: analysis)
        XCTAssertFalse(plan.tasks.contains { $0.id == "b" })
        XCTAssertEqual(plan.tasks.first { $0.id == "c" }?.dependsOn, ["a"])
    }

    func testLocalPlaceholdersAreReplacedByATaskSpecificStrategy() async throws {
        let plan = try await PromptOptimizer(provider: nil).optimize(.init(text: "make login more secure", mode: .auto))
        XCTAssertFalse(plan.optimizedPrompt.contains("Implement the change"))
        XCTAssertFalse(plan.optimizedPrompt.contains("Inspect the affected code"))
        XCTAssertFalse(plan.optimizedPrompt.contains("Possible causes or approaches"), "there were no real remedies to list")
        XCTAssertTrue(plan.tasks.contains { $0.title == "Review the existing security boundary" }, "\(plan.tasks.map(\.title))")
    }

    func testVagueOutcomeWordingIsGeneric() {
        for vague in ["The API is stable under load", "Database operations complete within expected timeframes", "Code is more readable and maintainable", "No recurring errors in the logs",
                      "The app runs faster and more reliably", "UI elements are visually consistent and improved", "Monitoring tools detect and alert on potential failures",
                      "Animations feel smooth and natural", "Each fixed problem was reproduced first and no longer occurs afterwards.",
                      "Existing interactions in the affected area still work after the fixes.", "Error logs show no patterns or trends",
                      "Accessible and compliant UI", "Functional and intuitive interaction states", "Consistent use of design tokens",
                      "No regressions in existing UI behavior", "Performance improvements are measurable and consistent",
                      "Code is free of redundancies and follows best practices", "Documentation is accurate and complete",
                      "Subtle interaction feedback for all states", "Accessibility compliance for all UI states",
                      "Animations respect user motion preferences", "No interference with user focus or accessibility",
                      "Consistent animation timing across all interactions", "No long-running transactions or locks",
                      "Improved query performance and reduced execution time", "Regression tests pass successfully"] {
            XCTAssertTrue(PromptQuality.genericCriterion(vague), vague)
        }
        for specific in ["A timed-out upload is retried up to 2 times", "The public API remains unchanged", "Each transition completes without visible snapping"] {
            XCTAssertFalse(PromptQuality.genericCriterion(specific), specific)
        }
    }

    func testGenericCriteriaAreReplacedByReportedSlowAndFailureChecks() {
        let request = "the app is slow and buggy fix it"
        let analysis = RequestAnalysis(request)
        var plan = PromptPlan(originalPrompt: request, intent: analysis.intent, taskType: .bugfix,
                              tasks: [.init(id: "a", title: "Reproduce the issue")],
                              successCriteria: ["The app runs faster and more reliably", "No new bugs are introduced"])

        PromptQuality.repair(&plan, analysis: analysis)

        XCTAssertFalse(plan.successCriteria.contains(where: PromptQuality.genericCriterion), "\(plan.successCriteria)")
        XCTAssertTrue(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("slow operation") })
        XCTAssertTrue(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("reported failure") })
        XCTAssertFalse(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("automated tests pass") }, "Test guidance belongs in Verification, not duplicated as acceptance criteria.")
    }

    func testDatabaseBoundariesDoNotBecomeSymptomsAndBroadBreakRuleIsGrammatical() async throws {
        let request = "Database operations are slow, intermittently fail, and time out under concurrent users. Fix the cause without changing the API or breaking anything."
        let plan = try await PromptOptimizer(provider: DatabaseProvider()).optimize(.init(text: request, mode: .advanced))

        XCTAssertEqual(plan.constraints.count, 2, "A constraint copied into separate model and local lists is emitted once: \(plan.constraints)\n\(plan.optimizedPrompt)")
        XCTAssertTrue(plan.constraints.contains { $0.localizedCaseInsensitiveContains("without changing the API") }, "the API rule remains a boundary: \(plan.constraints)\n\(plan.optimizedPrompt)")
        XCTAssertTrue(plan.constraints.contains { $0.localizedCaseInsensitiveContains("without breaking existing behavior") }, "generic break wording is normalized: \(plan.constraints)\n\(plan.optimizedPrompt)")
        XCTAssertFalse(plan.constraints.contains { $0.localizedCaseInsensitiveContains("Unchanged: breaking anything") })
        XCTAssertFalse(plan.suggestedDecisions.contains { $0.localizedCaseInsensitiveContains("reported behavior: without") })
        XCTAssertTrue(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("previously working behavior remains unchanged") }, "\(plan.successCriteria)")
        XCTAssertFalse(plan.confirmedRequirements.contains { $0.localizedCaseInsensitiveContains("operations are slow") }, "Symptoms belong in investigation work, not the requirements list.")
        XCTAssertFalse(plan.successCriteria.contains(where: PromptQuality.genericCriterion), "Absolute timeout promises must be replaced by reproducible checks: \(plan.successCriteria)")
        XCTAssertFalse(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("significantly faster") })
        XCTAssertFalse(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("consistent, reliable, and performant") })
        XCTAssertTrue(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("same concurrent workload") }, "\(plan.successCriteria)\n\(plan.optimizedPrompt)")
        XCTAssertFalse(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("reported slow operation") }, "A separate generic slow check duplicates the concurrent workload criterion.")
        XCTAssertTrue(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("API keeps its existing signature") }, "An unobservable model criterion must not suppress the API-preservation check: \(plan.successCriteria)")
        XCTAssertFalse(plan.tasks.contains { $0.title.range(of: #"(?i)\b(?:add|rebuild|reindex).*\bindexes?\b"#, options: .regularExpression) != nil }, "An index change is only considered if query-plan evidence supports it: \(plan.tasks.map(\.title))")
        XCTAssertFalse(plan.tasks.contains { $0.title.range(of: #"(?i)\b(?:optimi[sz]e|implement monitoring)\b"#, options: .regularExpression) != nil }, "Mentioning slow queries does not authorize a query-optimization or monitoring change: \(plan.tasks.map(\.title))")
        XCTAssertFalse(plan.suggestedDecisions.contains { $0.localizedCaseInsensitiveContains("profile slow database queries") }, "A diagnostic suggestion already covered by query-analysis work is redundant: \(plan.suggestedDecisions)")
        XCTAssertTrue(plan.optimizedPrompt.contains("connection-pool"), plan.optimizedPrompt)
        XCTAssertTrue(plan.optimizedPrompt.contains("lock contention"), plan.optimizedPrompt)
        XCTAssertTrue(plan.optimizedPrompt.contains("query-plan evidence"), plan.optimizedPrompt)
        XCTAssertFalse(plan.optimizedPrompt.contains("Rebuild database indexes."), "a proposed fix must not be an unconditional task")
        XCTAssertTrue(plan.optimizedPrompt.contains("only when query-plan evidence supports them"), plan.optimizedPrompt)
        XCTAssertFalse(plan.optimizedPrompt.localizedCaseInsensitiveContains("Definitions that matter here"), "Do not add a generic timeout glossary to a coding request.")
        XCTAssertTrue(plan.optimizedPrompt.localizedCaseInsensitiveContains("connection-pool waits"))
        XCTAssertFalse(plan.tasks.contains { $0.detail.localizedCaseInsensitiveContains("adjust database configuration") || $0.detail.localizedCaseInsensitiveContains("optimize queries as needed") },
                       "Do not carry an unverified remedy inside a generic fix task.")
        XCTAssertFalse(plan.tasks.contains { $0.detail.localizedCaseInsensitiveContains("optimize connection pooling") || $0.detail.localizedCaseInsensitiveContains("transaction isolation levels") },
                       "An inspection task can mention these as hypotheses, not prescribe adjustments before evidence.")
        let reproduction = plan.tasks.first { $0.title.localizedCaseInsensitiveContains("reproduc") }
        XCTAssertNotNil(reproduction, "Keep a distinct reproduction step: \(plan.tasks)")
        XCTAssertFalse(reproduction?.detail.localizedCaseInsensitiveContains("connection-pool waits") == true,
                       "Diagnostic candidates belong in analysis, not repeated in the reproduction step.")
        XCTAssertFalse(reproduction?.detail.localizedCaseInsensitiveContains("under the same load, inspect") == true,
                       "Do not duplicate the database diagnostic task under reproduction.")
        let diagnostic = plan.tasks.first { ($0.title + " " + $0.detail).localizedCaseInsensitiveContains("connection-pool waits") }
        XCTAssertNotNil(diagnostic, "Candidate causes should be grouped in a diagnostic task: \(plan.tasks)")
        XCTAssertFalse(diagnostic?.title.localizedCaseInsensitiveContains("reproduc") == true,
                       "The diagnostic checklist should not be attached to the reproduction task.")
    }

    func testDuplicateDiagnosticSuggestionIsRemovedAndTraced() async throws {
        struct DiagnosticProvider: LLMProvider {
            let identifier = "diagnostic-dedupe"
            func plan(for request: OptimizationRequest) async throws -> ModelPlan {
                ModelPlan(intent: request.analysis.intent, taskType: "performance", role: "", objective: request.analysis.intent,
                          suggestedDecisions: ["Profile slow database queries under concurrent load."],
                          tasks: [.init(id: "inspect", title: "Inspect query plans and profile slow database queries under concurrent load")])
            }
        }
        let request = "Database queries are slow under concurrent load. Investigate the cause."
        let plan = try await PromptOptimizer(provider: DiagnosticProvider()).optimize(.init(text: request, mode: .advanced))
        XCTAssertFalse(plan.suggestedDecisions.contains { $0.localizedCaseInsensitiveContains("profile slow database queries") })
        XCTAssertTrue(plan.trace?.events.contains { $0.stage == "quality" && $0.outcome == "removed" && $0.detail.contains("diagnostic covered by task") } == true,
                      "Expected a trace explaining the diagnostic dedupe: \(String(describing: plan.trace?.events))")
    }

    func testPreservedFiltersGetAnObservableNaturalCriterion() async throws {
        let request = "Add CSV export to monthly reports and keep the current date filters applied."
        let generated = ModelPlan(intent: "Add CSV export", taskType: "feature", role: "", objective: "Add CSV export to monthly reports",
                                  tasks: [.init(id: "t1", title: "Add CSV export")])
        let plan = try await PromptOptimizer(provider: StubProvider(result: .success(generated)))
            .optimize(.init(text: request, mode: .advanced))

        XCTAssertTrue(plan.constraints.contains { $0.localizedCaseInsensitiveContains("keep the current date filters applied") })
        XCTAssertTrue(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("date filters continue to apply") }, "\(plan.successCriteria)")
        XCTAssertFalse(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("unchanged:") }, "\(plan.successCriteria)")
    }

    func testIndependentDiagnosticsAreParallelAndVerificationFollowsImplementation() {
        let normalized = PromptQuality.normalizeDependencies([
            .init(id: "logs", title: "Review database logs"),
            .init(id: "query", title: "Inspect query plans", dependsOn: ["logs"]),
            .init(id: "cpu", title: "Monitor CPU usage", dependsOn: ["query"]),
            .init(id: "pool", title: "Investigate connection-pool waits", dependsOn: ["cpu"]),
            .init(id: "change", title: "Fix the measured bottleneck", dependsOn: ["cpu"]),
            .init(id: "verify", title: "Run regression tests", dependsOn: ["change"]),
        ])
        XCTAssertTrue(normalized.first { $0.id == "logs" }?.dependsOn.isEmpty == true)
        XCTAssertTrue(normalized.first { $0.id == "query" }?.dependsOn.isEmpty == true)
        XCTAssertTrue(normalized.first { $0.id == "cpu" }?.dependsOn.isEmpty == true)
        XCTAssertTrue(normalized.first { $0.id == "pool" }?.dependsOn.isEmpty == true)
        XCTAssertEqual(Set(normalized.first { $0.id == "change" }?.dependsOn ?? []), ["logs", "query", "cpu", "pool"])
        XCTAssertEqual(normalized.first { $0.id == "verify" }?.dependsOn, ["change"])
        XCTAssertNotNil(PromptComposer.topologicalOrder(normalized))
    }

    func testSemanticDuplicatesAcrossSuggestionsAndTasksAreRemoved() {
        let analysis = RequestAnalysis("the database is slow under concurrent load")
        var plan = PromptPlan(originalPrompt: analysis.text, intent: analysis.intent, taskType: .performance,
                              tasks: [.init(id: "profile", title: "Profile database query plans and measure slow queries")],
                              suggestedDecisions: ["Measure and profile the database query plans to find slow queries"],
                              verificationInstructions: ["Run the same workload after the change"])
        PromptQuality.repair(&plan, analysis: analysis)
        XCTAssertFalse(plan.suggestedDecisions.contains { $0.localizedCaseInsensitiveContains("profile database query plans") }, "the task already contains that investigation")
    }

    func testAReportedBottleneckDoesNotAuthorizeASpecificRemedy() {
        let request = "Database operations are slow under concurrent load. Find and fix the cause."
        var plan = PromptPlan(originalPrompt: request, intent: "Improve database performance", taskType: .performance,
                              tasks: [.init(id: "profile", title: "Use profiling tools to inspect query timings"),
                                      .init(id: "optimize", title: "Optimize slow queries"),
                                      .init(id: "monitor", title: "Implement monitoring"),
                                      .init(id: "api", title: "Optimize the API"),
                                      .init(id: "fix", title: "Fix confirmed issues")])
        PromptQuality.repair(&plan, analysis: RequestAnalysis(request))
        XCTAssertTrue(plan.tasks.contains { $0.id == "profile" }, "Diagnostic methods are investigation guidance")
        XCTAssertFalse(plan.tasks.contains { $0.id == "optimize" || $0.id == "monitor" }, "A reported symptom does not authorize a remedy")
        XCTAssertTrue(plan.suggestedDecisions.contains { $0.localizedCaseInsensitiveContains("optimize slow queries") })
        XCTAssertFalse(plan.suggestedDecisions.contains { $0.localizedCaseInsensitiveContains("Optimize the API") || $0.localizedCaseInsensitiveContains("Implement monitoring") }, "Vague remedies add no value even as conditional suggestions")

        let specifiedRequest = "Optimize slow database queries after profiling."
        var specified = PromptPlan(originalPrompt: specifiedRequest, intent: "Optimize slow queries", taskType: .performance,
                                   tasks: [.init(id: "optimize", title: "Optimize slow queries")])
        PromptQuality.repair(&specified, analysis: RequestAnalysis(specifiedRequest))
        XCTAssertTrue(specified.tasks.contains { $0.id == "optimize" }, "An explicitly named action remains a requested implementation")
    }

    func testReportedSymptomsAreNotDuplicatedAsConfirmedRequirements() {
        let request = "The settings view opens slowly, switching back to the main view freezes, and buttons stop responding. Find and fix the cause."
        let analysis = RequestAnalysis(request)
        var plan = PromptPlan(originalPrompt: request, intent: analysis.intent, taskType: .bugfix,
                              tasks: [.init(id: "repro", title: "Reproduce the issue", detail: "Record the steps that trigger the freeze.")],
                              successCriteria: [], confirmedRequirements: ["Switching back to the main view freezes", "Buttons stop responding"],
                              verificationInstructions: [])
        PromptQuality.repair(&plan, analysis: analysis)
        XCTAssertTrue(plan.confirmedRequirements.isEmpty, "Observed failures belong in investigation, not the requirements section.")
        XCTAssertFalse(plan.optimizedPrompt.contains("## Requirements (stated by the user)"))
        XCTAssertTrue(plan.tasks.first?.detail.localizedCaseInsensitiveContains("buttons stop responding") == true)
    }

    func testSignificantlyFasterWithoutAComparisonIsGeneric() {
        XCTAssertTrue(PromptQuality.genericCriterion("The database is significantly faster."))
        XCTAssertTrue(PromptQuality.genericCriterion("No timeout occurs under concurrent load."))
        XCTAssertTrue(PromptQuality.genericCriterion("Dark mode is toggled on and off smoothly."))
        XCTAssertTrue(PromptQuality.genericCriterion("All UI elements are styled correctly in dark mode."))
        XCTAssertTrue(PromptQuality.genericCriterion("No new errors or failures in the database layer."))
        XCTAssertTrue(PromptQuality.genericCriterion("No API changes or functionality regressions"))
        XCTAssertTrue(PromptQuality.genericCriterion("No API changes"))
        XCTAssertTrue(PromptQuality.genericCriterion("No functional regressions"))
        XCTAssertTrue(PromptQuality.genericCriterion("No new issues or regressions in existing functionality"))
        XCTAssertTrue(PromptQuality.genericCriterion("No API changes or functionality breaks"))
        XCTAssertTrue(PromptQuality.genericCriterion("The settings view opens quickly"))
        XCTAssertTrue(PromptQuality.genericCriterion("Switching views feels smooth"))
        XCTAssertTrue(PromptQuality.genericCriterion("Buttons respond promptly"))
        XCTAssertTrue(PromptQuality.genericCriterion("Database operations are consistent and reliable under concurrent users"))
        XCTAssertTrue(PromptQuality.genericCriterion("Database operations are consistent, reliable, and performant under concurrent users."))
        XCTAssertFalse(PromptQuality.genericCriterion("Compare the same workload before and after and report the measured latency."))
    }

    func testGenericCriteriaAreRemovedEvenWhenTheRequestDoesNotNeedAFullQualityPlaybook() {
        let analysis = RequestAnalysis("add dark mode")
        var plan = PromptPlan(originalPrompt: analysis.text, intent: analysis.intent, taskType: analysis.taskType,
                              successCriteria: ["Dark mode is toggled on and off smoothly", "All UI elements are styled correctly in dark mode"])
        PromptQuality.repair(&plan, analysis: analysis)
        XCTAssertTrue(plan.successCriteria.isEmpty, "Removing vague criteria should not inflate a simple request with filler.")
    }
}
