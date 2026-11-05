import XCTest
@testable import RefineCore

final class PromptEngineeringTests: XCTestCase {
    func testAutoKeepsSimpleRequestSimple() async throws {
        let plan = try await PromptEngineeringService().optimize("Rename this variable", mode: .auto)
        XCTAssertEqual(plan.selectedTechniques, [.zeroShot])
        XCTAssertEqual(plan.optimizedPrompt, "Rename this variable")
    }

    func testAdvancedAddsObservableStepsAndBoundedVerification() async throws {
        let prompt = "Implement a feature with tests, update the relevant interfaces, preserve existing behavior, and explain all changes made in the project."
        let plan = try await PromptEngineeringService().optimize(prompt, mode: .advanced)
        XCTAssertTrue(plan.optimizedPrompt.contains("Task steps:"))
        XCTAssertTrue(plan.optimizedPrompt.contains("up to 3 attempts"))
        XCTAssertEqual(plan.iterationLimit, 3)
        XCTAssertEqual(plan.originalPrompt, prompt)
    }

    func testEmptyPromptIsRejected() async {
        do {
            _ = try await PromptEngineeringService().optimize(" \n", mode: .basic)
            XCTFail("Expected empty input to fail")
        } catch { XCTAssertTrue(error is PromptError) }
    }

    func testPlanPersistenceRoundTrip() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        let store = PromptPlanService(fileURL: file)
        let plan = try await PromptEngineeringService().optimize("Fix the parser", mode: .basic)
        try await store.save(plan)
        let reloaded = PromptPlanService(fileURL: file)
        let loadedPlans = await reloaded.allPlans()
        XCTAssertEqual(loadedPlans.map(\.originalPrompt), ["Fix the parser"])
        try? FileManager.default.removeItem(at: file)
    }
}
