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
        XCTAssertTrue(plan.suggestedDecisions.contains { $0.hasPrefix("Consider only if") && $0.contains("multi-factor") })
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
        XCTAssertEqual(plan.tasks.first?.title, "Locate the code that implements this")
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
        XCTAssertTrue(plan.constraints.contains("Don't mess up the design"), "\(plan.constraints)")
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
        XCTAssertTrue(plan.suggestedDecisions.contains { $0.localizedCaseInsensitiveContains("UI freezes") }, "The reported freeze must remain an investigation target.")
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
        let conditional = plan.suggestedDecisions.filter { $0.hasPrefix("Consider only if") }
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
        XCTAssertFalse(plan.optimizedPrompt.contains("Consider only if"), "there were no real remedies to list")
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
}
