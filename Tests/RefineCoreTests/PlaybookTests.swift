import XCTest
@testable import RefineCore

final class PlaybookTests: XCTestCase {
    private func optimize(_ text: String, mode: PromptMode = .auto) async throws -> PromptPlan {
        try await PromptOptimizer(provider: nil).optimize(.init(text: text, mode: mode))
    }

    func testVagueAnimationComplaintGainsDepthLabelledAsSuggested() async throws {
        let plan = try await optimize("the animation for opening the notch is bad")
        XCTAssertEqual(plan.guidance?.topic, "Animation and motion quality")
        let prompt = plan.optimizedPrompt
        print(prompt)
        for expected in ["Investigate first", "What good looks like (suggested bar, not stated by the user", "Examples of the target quality",
                         "ease-out", "Reduce Motion", "Bad:", "Good:", "the notch"] {
            XCTAssertTrue(prompt.contains(expected), "Missing: \(expected)")
        }
        XCTAssertTrue(plan.confirmedRequirements.allSatisfy { !$0.contains("250 ms") }, "Playbook values are suggestions, never confirmed requirements.")
    }

    func testDetailedRequestIsNotPaddedWithPlaybook() async throws {
        let plan = try await optimize("Change the notch open animation in NotchRootView.swift to a 300ms ease-out, keep the close animation as it is, and add a Reduce Motion cross-fade. Update the snapshot tests and make sure the panel still collapses when the user clicks outside it.")
        XCTAssertNil(plan.guidance)
    }

    func testOtherTopicsMatch() {
        let ctx = RetrievedContext(workspaceName: "", languages: [], frameworks: [], components: [], notes: [], analyzed: false)
        func topic(_ s: String) -> String? { Playbook.match(RequestAnalysis(s), context: ctx)?.topic }
        XCTAssertEqual(topic("search is really slow"), "Performance")
        XCTAssertEqual(topic("the settings page looks ugly"), "Visual design quality")
        XCTAssertEqual(topic("login is broken"), "Bug investigation")
        XCTAssertNil(topic("rename the User model to Account"))
    }

    func testCreationAndComplaintMotionRouting() async throws {
        let ctx = RetrievedContext(workspaceName: "", languages: ["TypeScript"], frameworks: ["React", "CSS"], components: [], notes: [], analyzed: false)
        let creation = "we want to add like a cool cursor animation to my personal website, we want it to be baby blue themed. make it cool"
        let created = try XCTUnwrap(Playbook.match(RequestAnalysis(creation), context: ctx))
        XCTAssertEqual(created.kind, .create)
        let creationPlan = try await optimize(creation)
        let createPrompt = creationPlan.optimizedPrompt
        print("Creative animation prompt:\n\(createPrompt)")
        for forbidden in ["does not say what exactly is wrong", "Reproduce it", "Name the symptom", "corner radius", "reversal"] {
            XCTAssertFalse(createPrompt.localizedCaseInsensitiveContains(forbidden), "Unexpected: \(forbidden)")
        }
        XCTAssertTrue(createPrompt.localizedCaseInsensitiveContains("baby blue"))
        XCTAssertTrue(createPrompt.localizedCaseInsensitiveContains("cursor"))
        XCTAssertEqual(Playbook.match(RequestAnalysis("we want to add a fade-in animation to the hero"), context: ctx)?.kind, .create)
        XCTAssertEqual(Playbook.match(RequestAnalysis("can you build a loading spinner"), context: ctx)?.kind, .create)
        XCTAssertEqual(Playbook.match(RequestAnalysis("the panel open animation is janky"), context: ctx)?.kind, .diagnose)
        XCTAssertEqual(Playbook.match(RequestAnalysis("fix the stutter when the sidebar collapses"), context: ctx)?.kind, .diagnose)
        XCTAssertEqual(Playbook.match(RequestAnalysis("add a modal that expands smoothly"), context: ctx)?.kind, .create)
        XCTAssertEqual(Playbook.pace(in: "make it cool").1, "cool")
    }

    func testCreativeRequestRoutesToModelAndNoProviderUsesCreatePlan() async throws {
        let request = "we want to add like a cool cursor animation to my personal website, we want it to be baby blue themed. make it cool"
        let generated = ModelPlan(
            intent: request, taskType: "feature", role: "A web designer and front-end engineer",
            objective: "Add a cool cursor animation to the personal website using a baby blue theme.",
            confirmedRequirements: ["Add a cursor animation", "Use a baby blue theme"],
            tasks: [.init(id: "t1", title: "Inspect the existing site style"), .init(id: "t2", title: "Add the cursor animation")],
            successCriteria: ["The cursor animation uses the requested baby blue theme."])
        let providerPlan = try await PromptOptimizer(provider: StubProvider(result: .success(generated)))
            .optimize(.init(text: request, mode: .auto))
        XCTAssertEqual(providerPlan.trace?.modelCalls, 1)
        XCTAssertNotEqual(providerPlan.provider, "local")
        print("Stub-provider creation prompt:\n\(providerPlan.optimizedPrompt)")

        let localPlan = try await optimize(request)
        XCTAssertEqual(localPlan.guidance?.kind, .create)
        for forbidden in ["does not say what exactly is wrong", "Reproduce it", "Name the symptom", "corner radius", "reversal"] {
            XCTAssertFalse(localPlan.optimizedPrompt.localizedCaseInsensitiveContains(forbidden), "Unexpected diagnostic content: \(forbidden)")
        }
        XCTAssertTrue(localPlan.optimizedPrompt.localizedCaseInsensitiveContains("baby blue"))
        XCTAssertTrue(localPlan.optimizedPrompt.localizedCaseInsensitiveContains("cursor"))
        print("No-provider creation prompt:\n\(localPlan.optimizedPrompt)")
    }

    func testCreativeModelPathMergesInteractiveGuidanceAndRepairsWeakOutput() async throws {
        let request = "we want to add a cool hover effect to the buttons on my portfolio, kinda glowy, idk make it pop"
        let generated = ModelPlan(
            intent: request, taskType: "feature", role: "A web designer and front-end engineer",
            objective: "Add a cool, glowing hover effect to the portfolio buttons and make it pop.",
            confirmedRequirements: [request],
            suggestedDecisions: ["Ensure the effect is subtle and not overbearing."],
            tasks: [.init(id: "t1", title: "Locate the relevant code path", detail: "Locate all buttons in the portfolio layout and implement the hover effect.")],
            successCriteria: ["The effect is visually appealing"])
        let plan = try await PromptOptimizer(provider: StubProvider(result: .success(generated)))
            .optimize(.init(text: request, mode: .auto))
        let prompt = plan.optimizedPrompt.lowercased()

        XCTAssertEqual(plan.trace?.modelCalls, 1)
        for expected in [":focus-visible", "prefers-reduced-motion", "touch devices", "existing palette", "duration and easing"] {
            XCTAssertTrue(prompt.contains(expected), "Missing model-path creative guidance: \(expected)\n\(plan.optimizedPrompt)")
        }
        XCTAssertFalse(prompt.contains("subtle and not overbearing"))
        XCTAssertFalse(prompt.contains("visually appealing"))
        XCTAssertFalse(prompt.contains("locate the relevant code path. locate all buttons"))
        XCTAssertFalse(prompt.contains("## Requirements"), "The requirement merely repeated the objective.\n\(plan.optimizedPrompt)")
        XCTAssertTrue(plan.successCriteria.contains { $0.localizedCaseInsensitiveContains("hover") && $0.localizedCaseInsensitiveContains("keyboard focus") })
        XCTAssertTrue(plan.trace?.events.contains { $0.stage == "semantic" && $0.outcome == "removed" && $0.detail.contains("visual direction") } == true)
        print("Creative hover effect prompt (stub provider):\n\(plan.optimizedPrompt)")
    }

    func testCreativeLocalPathIncludesInteractiveAccessibilityGuidance() async throws {
        let request = "we want to add a cool hover effect to the buttons on my portfolio, kinda glowy, idk make it pop"
        let plan = try await optimize(request)
        let prompt = plan.optimizedPrompt.lowercased()
        XCTAssertEqual(plan.guidance?.kind, .create)
        for expected in [":focus-visible", "prefers-reduced-motion", "touch devices", "existing palette", "duration and easing"] {
            XCTAssertTrue(prompt.contains(expected), "Missing local creative guidance: \(expected)\n\(plan.optimizedPrompt)")
        }
        XCTAssertFalse(prompt.contains("subtle"))
        print("Creative hover effect prompt (no provider):\n\(plan.optimizedPrompt)")
    }

    func testExpressiveRequestRemovesOppositeIntensityAndRecordsCorrection() async throws {
        let request = "Add a bold animation and make it pop"
        let model = ModelPlan(intent: request, taskType: "feature", role: "", objective: "Add a bold animation that makes it pop.",
                              suggestedDecisions: ["The animation feels subtle and understated."])
        let plan = try await PromptOptimizer(provider: StubProvider(result: .success(model)))
            .optimize(.init(text: request, mode: .advanced))
        XCTAssertFalse(plan.optimizedPrompt.localizedCaseInsensitiveContains("subtle"))
        XCTAssertTrue(plan.trace?.events.contains { $0.stage == "semantic" && $0.outcome == "removed" && $0.detail.contains("restrained wording") } == true,
                      "The correction should be visible in the pipeline trace: \(String(describing: plan.trace?.events))")
    }

    func testRestrainedRequestRemovesOppositeIntensity() {
        let request = "Keep the transition subtle and minimal"
        let model = ModelPlan(intent: request, taskType: "ui", role: "", objective: "Keep the transition subtle and minimal.",
                              suggestedDecisions: ["Make it bold and eye-catching."])
        let (corrected, changes) = SemanticValidator.correctWithReport(model, analysis: RequestAnalysis(request))
        XCTAssertTrue(corrected.suggestedDecisions.isEmpty)
        XCTAssertTrue(changes.contains { $0.action == .removed && $0.reason.contains("expressive wording") })
    }

    func testUnspecifiedIntensityDoesNotRemoveSuggestion() {
        let request = "Add an animation to the page"
        let suggestion = "The animation can feel subtle and understated."
        let model = ModelPlan(intent: request, taskType: "feature", role: "", objective: "Add an animation to the page.",
                              suggestedDecisions: [suggestion])
        let (corrected, changes) = SemanticValidator.correctWithReport(model, analysis: RequestAnalysis(request))
        XCTAssertEqual(corrected.suggestedDecisions, [suggestion])
        XCTAssertFalse(changes.contains { $0.reason.contains("visual direction") })
    }

    func testCreativeDefaultsOnlyMentionBuildAndTestsWhenContextShowsSetup() {
        let empty = RetrievedContext(workspaceName: "", languages: [], frameworks: [], components: [], notes: [], analyzed: false)
        let setup = RetrievedContext(workspaceName: "site", languages: ["TypeScript"], frameworks: ["React"], components: [
            .init(id: "manifest", name: "Package", type: "file", path: "package.json", files: ["src/hero.test.ts"], symbols: [], routes: [], connectsTo: [])
        ], notes: [], analyzed: true)
        let analysis = RequestAnalysis("we want to add a fade-in animation to the hero")
        let noSetupPlan = PromptOptimizer.localPlan(analysis: analysis, context: empty)
        let setupPlan = PromptOptimizer.localPlan(analysis: analysis, context: setup)
        XCTAssertTrue(noSetupPlan.successCriteria.contains("The requested feature works and matches the stated style."))
        XCTAssertFalse(noSetupPlan.successCriteria.contains("Existing tests and the build pass."))
        XCTAssertTrue(setupPlan.successCriteria.contains("Existing tests and the build pass."))
        XCTAssertEqual(setupPlan.tasks.first?.title, "Inspect where the feature belongs")
    }

    func testStackSpecificHintsOnlyWhenStackKnown() {
        let swift = RetrievedContext(workspaceName: "w", languages: ["Swift"], frameworks: ["SwiftUI"], components: [], notes: [], analyzed: true)
        XCTAssertTrue(Playbook.motion(swift).goodLooksLike.contains { $0.contains("Apple platforms") })
        let none = RetrievedContext(workspaceName: "", languages: [], frameworks: [], components: [], notes: [], analyzed: false)
        XCTAssertFalse(Playbook.motion(none).goodLooksLike.contains { $0.contains("Apple platforms") })
    }

    func testSlowSmoothRequestGetsSlowNumbersNotFastOnes() async throws {
        let plan = try await optimize("im building an notch app fix this prompt: it should be like a very slow opening and closing and smooth")
        let prompt = plan.optimizedPrompt
        print(prompt)
        XCTAssertEqual(plan.guidance?.direction, "very slow, smooth")
        XCTAssertFalse(prompt.contains("800–1200 ms"), "A qualitative pace is not authorization to invent a target.")
        XCTAssertTrue(prompt.contains("soft ease-in-out"))
        XCTAssertTrue(prompt.contains("corner radius"))
        XCTAssertTrue(prompt.contains("Target quality (derived from your request"))
        XCTAssertFalse(prompt.contains("200–350 ms"), "A request for slow motion must not be pulled toward fast defaults.")
        XCTAssertFalse(prompt.components(separatedBy: "## Objective\n").dropFirst().first?.components(separatedBy: "\n\n").first?.contains("im building") ?? true,
                       "The meta preface should not leak into the objective.")
        XCTAssertTrue(prompt.contains("very slow opening and closing") || prompt.contains("very slow, smooth"))
    }

    func testFastRequestGetsFastNumbers() {
        let ctx = RetrievedContext(workspaceName: "", languages: [], frameworks: [], components: [], notes: [], analyzed: false)
        let g = Playbook.match(RequestAnalysis("make the menu open snappy and quick"), context: ctx)
        XCTAssertTrue(g?.goodLooksLike.first?.contains("fast response") == true)
    }
}
