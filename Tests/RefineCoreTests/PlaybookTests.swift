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
