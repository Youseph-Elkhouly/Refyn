import XCTest
@testable import RefineCore

/// Exercises the retained analyzer and context retrieval against the real helper.
final class WorkspaceAnalyzerIntegrationTests: XCTestCase {
    var dir: URL!
    var project: URL!
    var helper: HelperClient!
    var store: WorkspaceStore!
    var analyzer: WorkspaceAnalyzer!

    override func setUp() async throws {
        let script = Fixtures.repoRoot.appending(path: "RefineHelper/dist/src/main.js")
        guard FileManager.default.fileExists(atPath: script.path), (try? HelperClient.locateNode(override: nil)) != nil else {
            throw XCTSkip("Node.js or the built helper is unavailable")
        }
        dir = try Fixtures.temporaryDirectory()
        setenv("REFINE_SUPPORT_DIR", dir.appending(path: "support").path, 1)
        project = dir.appending(path: "sample-app")
        try FileManager.default.copyItem(at: Fixtures.sampleApp, to: project)
        helper = HelperClient(helperScript: script, idleTimeout: .seconds(5))
        analyzer = WorkspaceAnalyzer(helper: helper)
        store = try WorkspaceStore(databaseURL: dir.appending(path: "refine.sqlite"))
    }

    override func tearDown() async throws {
        await helper?.stop()
        unsetenv("REFINE_SUPPORT_DIR")
        if let dir { try? FileManager.default.removeItem(at: dir) }
    }

    func testWorkspaceAnalysisFeedsRelevantPromptContext() async throws {
        let workspace = try await store.addDirectory(project)
        let outcome = try await analyzer.analyze(workspace)
        XCTAssertNotNil(outcome.graph.node("mod:src/services"))
        XCTAssertTrue(outcome.graph.metadata.languages.contains { $0.name == "TypeScript" && $0.analyzed })
        let analysis = RequestAnalysis("Update listUsers in the service")
        let context = ContextRetriever.retrieve(for: analysis, workspaceName: workspace.name, graph: outcome.graph, notes: [])
        XCTAssertTrue(context.components.contains { $0.files.contains("src/services/users.ts") || $0.symbols.contains { $0.contains("listUsers") } })
        XCTAssertFalse(context.knownPaths.contains(where: { $0.contains(".env") }))
    }

    func testHelperRestartsAfterStop() async throws {
        let workspace = try await store.addDirectory(project)
        _ = try await analyzer.analyze(workspace)
        await helper.stop()
        let stopped = await helper.isRunning
        XCTAssertFalse(stopped)
        _ = try await analyzer.analyze(workspace)
        let restarted = await helper.isRunning
        XCTAssertTrue(restarted)
    }
}
