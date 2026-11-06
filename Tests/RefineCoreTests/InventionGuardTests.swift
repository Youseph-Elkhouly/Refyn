import XCTest
@testable import RefineCore

final class InventionGuardTests: XCTestCase {
    func context(paths: [String] = ["src/services/users.ts"], symbols: [String] = ["listUsers"]) -> RetrievedContext {
        RetrievedContext(workspaceName: "app", languages: ["TypeScript"], frameworks: [],
                         components: [.init(id: "mod:src/services", name: "services", type: "service", path: "src/services", files: paths,
                                            symbols: symbols, routes: ["/api/users", "/api/users/:id"], connectsTo: [])],
                         notes: [], analyzed: true)
    }

    func guarded(_ plan: ModelPlan, request: String = "add pagination to listUsers in src/services/users.ts", ctx: RetrievedContext? = nil) -> InventionGuard.Result {
        InventionGuard.apply(to: plan, analysis: RequestAnalysis(request), context: ctx ?? context(), allowedNumbers: [3])
    }

    func testInventedPathNumberAndIdentifierAreDemotedFromConfirmedRequirements() {
        var plan = ModelPlan.sample()
        plan.confirmedRequirements = ["Paginate `listUsers`", "Edit src/db/migrations.ts", "Respond within 250ms", "Call fetchAllUsers"]
        let result = guarded(plan)
        XCTAssertEqual(result.plan.confirmedRequirements, ["Paginate `listUsers`"])
        XCTAssertEqual(Set(result.demoted), ["Edit src/db/migrations.ts", "Respond within 250ms", "Call fetchAllUsers"])
        XCTAssertTrue(result.plan.suggestedDecisions.contains("Respond within 250ms"))
    }

    func testInventedConstraintBecomesSuggestion() {
        var plan = ModelPlan.sample()
        plan.constraints = ["Do not change `listUsers` response shape", "Keep page size at 50 rows"]
        let result = guarded(plan)
        XCTAssertEqual(result.plan.constraints, ["Do not change `listUsers` response shape"])
        XCTAssertTrue(result.plan.suggestedDecisions.contains("Keep page size at 50 rows"))
    }

    func testTermsFromRequestContextAndAnswersPass() {
        var plan = ModelPlan.sample()
        plan.confirmedRequirements = ["Update src/services/users.ts", "Keep GET /api/users working", "Retry up to 7 times, as you asked"]
        let result = InventionGuard.apply(to: plan, analysis: RequestAnalysis("retry up to 7 times in listUsers", confirmedRequirements: ["Keep GET /api/users working"]),
                                          context: context(), allowedNumbers: [])
        XCTAssertEqual(result.plan.confirmedRequirements.count, 3)
        XCTAssertTrue(result.demoted.isEmpty)
    }

    func testUnsupportedSmallNumbersAreCaughtButConfiguredLimitsAndAbbreviationsPass() {
        var plan = ModelPlan.sample()
        plan.confirmedRequirements = ["Add 2 tests, e.g. empty page", "Stop after 3 attempts"]
        let result = guarded(plan)
        XCTAssertEqual(result.plan.confirmedRequirements, ["Stop after 3 attempts"])
        XCTAssertTrue(result.demoted.contains("Add 2 tests, e.g. empty page"))
    }

    func testUnsupportedDetailsAreRemovedFromTasksAndMovedToSuggestions() {
        var plan = ModelPlan.sample()
        plan.tasks = [
            .init(id: "a", title: "Edit config/pagination.json", detail: "", dependsOn: []),
            .init(id: "b", title: "Add tests", detail: "", dependsOn: ["a"]),
        ]
        plan.successCriteria = []
        plan.verificationSteps = ["Run npm test", "Check `listUsers` returns a cursor"]
        let result = guarded(plan)
        XCTAssertTrue(result.plan.tasks.isEmpty, "The invalid task and its dependent task must not remain actionable.")
        XCTAssertTrue(result.plan.suggestedDecisions.contains { $0.contains("config/pagination.json") })
        XCTAssertEqual(result.plan.verificationSteps, ["Run npm test", "Check `listUsers` returns a cursor"])
        XCTAssertEqual(result.unverified, ["config/pagination.json"])
        XCTAssertFalse(result.notices.isEmpty)
    }

    func testInventedURLAndLibraryAreCaughtButRequestAndContextTermsPass() {
        var plan = ModelPlan.sample()
        plan.confirmedRequirements = ["Call https://api.example.com/invite and use Redis"]
        let result = guarded(plan)
        XCTAssertTrue(result.demoted.contains { $0.contains("Redis") })
        XCTAssertTrue(result.demoted.contains { $0.contains("https://api.example.com/invite") })

        let supplied = InventionGuard.apply(to: plan, analysis: RequestAnalysis("Use Redis at https://api.example.com/invite"),
                                            context: context(), allowedNumbers: [])
        XCTAssertTrue(supplied.plan.confirmedRequirements.contains { $0.localizedCaseInsensitiveContains("Redis") })
        XCTAssertTrue(supplied.plan.confirmedRequirements.contains { $0.contains("https://api.example.com/invite") })
    }

    func testCleanPlanProducesNoNotices() {
        var plan = ModelPlan.sample()
        plan.successCriteria = ["`listUsers` returns a cursor"]
        XCTAssertTrue(guarded(plan).notices.isEmpty)
    }

    func testReasoningBlocksAreStrippedBeforeJSONExtraction() {
        XCTAssertEqual(ModelOutput.jsonObject(from: "<think>use {x} here</think>\n{\"a\":1}"), "{\"a\":1}")
        XCTAssertEqual(ModelOutput.jsonObject(from: "reasoning without opener</think>{\"a\":1}"), "{\"a\":1}")
        XCTAssertEqual(ModelOutput.jsonObject(from: "{\"a\":{\"b\":2}}"), "{\"a\":{\"b\":2}}")
        XCTAssertEqual(ModelOutput.jsonObject(from: "<THINK>a</THINK>{\"a\":1}<think>b</think>"), "{\"a\":1}")
        XCTAssertNil(ModelOutput.jsonObject(from: "<think>never closed {\"a\":1}"))
        XCTAssertNil(ModelOutput.jsonObject(from: "no json"))
    }

    func testEndDetectorStopsAtFirstClosedObjectAcrossChunks() {
        var detector = JSONObjectEndDetector()
        XCTAssertFalse(detector.feed("<think>\n{ not json }\n"))
        XCTAssertFalse(detector.feed("</think>\n{\"a\":\"x}\\\"}\","))
        XCTAssertFalse(detector.feed("\"b\":{\"c\":[1,2]"))
        XCTAssertTrue(detector.feed("}}"))
    }
}
