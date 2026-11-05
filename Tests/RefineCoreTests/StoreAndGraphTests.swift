import GRDB
import XCTest
@testable import RefineCore

final class StoreAndGraphTests: XCTestCase {
    var dir: URL!
    var store: WorkspaceStore!

    override func setUpWithError() throws {
        dir = try Fixtures.temporaryDirectory()
        store = try WorkspaceStore(databaseURL: dir.appending(path: "refine.sqlite"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testWorkspaceLifecycleNeverTouchesTheProject() async throws {
        let project = dir.appending(path: "project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "keep me".write(to: project.appending(path: "file.txt"), atomically: true, encoding: .utf8)

        let ws = try await store.addDirectory(project)
        do { _ = try await store.addDirectory(project); XCTFail("duplicate allowed") } catch {}
        try await store.rename(ws.id, to: "Renamed")
        let renamed = try await store.workspace(ws.id)
        XCTAssertEqual(renamed?.name, "Renamed")

        try await store.save(Note(workspaceID: ws.id, title: "Auth", body: "Uses JWT"))
        try await store.save(SavedPrompt(workspaceID: ws.id, title: "Pagination", prompt: "Add pagination"))
        try await store.remove(ws.id)
        let remaining = try await store.workspaces()
        XCTAssertTrue(remaining.isEmpty)
        let notes = try await store.notes(workspaceID: ws.id)
        XCTAssertTrue(notes.isEmpty, "notes cascade with the workspace")
        XCTAssertEqual(try String(contentsOf: project.appending(path: "file.txt"), encoding: .utf8), "keep me")
    }

    func testNotesAndSavedPromptsSearch() async throws {
        let ws = try await store.addDirectory(dir)
        try await store.save(Note(workspaceID: ws.id, title: "Auth", body: "Uses JWT tokens", includeInContext: false))
        try await store.save(Note(workspaceID: ws.id, title: "Deploy", body: "Vercel"))
        let jwt = try await store.notes(workspaceID: ws.id, matching: "jwt")
        XCTAssertEqual(jwt.map(\.title), ["Auth"])
        XCTAssertEqual(jwt.first?.includeInContext, false)

        var saved = SavedPrompt(workspaceID: ws.id, title: "Pagination", prompt: "Add pagination")
        try await store.save(saved)
        saved.prompt = "Add cursor pagination"
        try await store.save(saved)
        let found = try await store.savedPrompts(workspaceID: ws.id, matching: "cursor")
        XCTAssertEqual(found.map(\.prompt), ["Add cursor pagination"])
        try await store.deleteSavedPrompt(saved.id)
        let afterDelete = try await store.savedPrompts(workspaceID: ws.id)
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testPlansPersistAndServeAsCache() async throws {
        let ws = try await store.addDirectory(dir)
        var plan = try await PromptOptimizer(provider: nil).optimize(.init(text: "Fix the parser", mode: .basic, workspace: ws))
        plan.workspaceID = ws.id
        try await store.save(plan)
        let found = try await store.cachedPlan(cacheKey: plan.cacheKey)
        let cached = try XCTUnwrap(found)
        XCTAssertEqual(cached.id, plan.id)
        XCTAssertEqual(cached.optimizedPrompt, plan.optimizedPrompt)
        XCTAssertEqual(cached.tasks, plan.tasks)
        XCTAssertEqual(cached.createdAt.timeIntervalSince1970, plan.createdAt.timeIntervalSince1970, accuracy: 0.001)
        let listed = try await store.plans(workspaceID: ws.id)
        XCTAssertEqual(listed.map(\.originalPrompt), ["Fix the parser"])
    }

    func testSnapshotsAreVersioned() async throws {
        let ws = try await store.addDirectory(dir)
        let g = try Fixtures.graph()
        let v1 = try await store.appendSnapshot(ArchitectureSnapshot(workspaceID: ws.id, version: 0, label: "scan", verified: true, graph: g))
        let v2 = try await store.appendSnapshot(ArchitectureSnapshot(workspaceID: ws.id, version: 0, label: "rejected", verified: false, graph: g))
        XCTAssertEqual([v1.version, v2.version], [1, 2])
        let latestVerified = try await store.latestSnapshot(workspaceID: ws.id)
        XCTAssertEqual(latestVerified?.id, v1.id)
        let latestAny = try await store.latestSnapshot(workspaceID: ws.id, verifiedOnly: false)
        XCTAssertEqual(latestAny?.id, v2.id)
    }

    func testV1DatabaseMigratesNotes() async throws {
        let url = dir.appending(path: "old.sqlite")
        let queue = try DatabaseQueue(path: url.path)
        var v1 = DatabaseMigrator()
        v1.registerMigration("create-workspaces-and-prompts") { db in
            try db.execute(sql: """
                CREATE TABLE workspaces (id TEXT PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL UNIQUE, bookmark BLOB, notes TEXT NOT NULL DEFAULT '', createdAt DOUBLE NOT NULL, lastOpenedAt DOUBLE NOT NULL);
                CREATE TABLE savedPrompts (id TEXT PRIMARY KEY, workspaceID TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE, title TEXT NOT NULL, prompt TEXT NOT NULL, createdAt DOUBLE NOT NULL);
                """)
        }
        try v1.migrate(queue)
        let id = UUID()
        try await queue.write { db in
            try db.execute(sql: "INSERT INTO workspaces VALUES (?, 'old', '/tmp/old', NULL, 'remember this', 0, 0)", arguments: [id.uuidString])
        }
        try queue.close()
        let migrated = try WorkspaceStore(databaseURL: url)
        let notes = try await migrated.notes(workspaceID: id)
        XCTAssertEqual(notes.map(\.body), ["remember this"])
    }

    func testArchitectureDiff() throws {
        let old = try Fixtures.graph()
        var nodes = old.nodes
        nodes[1].symbols.append(GraphSymbol(name: "paginate", kind: "function", path: "src/services/users.ts", line: 9))
        nodes.append(GraphNode(id: "ext:pg", name: "pg", type: .external, path: ""))
        let edges = old.edges + [
            GraphEdge(source: "mod:src/services", target: "ext:pg", relation: "uses-database", evidence: [SourceRef(path: "src/services/users.ts", line: 1)], verification: .confirmed),
            GraphEdge(source: "mod:src/server", target: "mod:src/services", relation: "calls-api", verification: .inferred),
        ]
        let diff = ArchitectureDiff.between(old, try Fixtures.graph(nodes: nodes, edges: edges))
        XCTAssertEqual(diff.addedNodes.map(\.id), ["ext:pg"])
        XCTAssertEqual(diff.modifiedNodes.map(\.id), ["mod:src/services"])
        XCTAssertEqual(diff.modifiedNodes.first?.addedSymbols, ["function paginate"])
        XCTAssertEqual(diff.addedEdges.count, 2)
        XCTAssertEqual(diff.unverifiedEdges.map(\.relation), ["calls-api"])
        XCTAssertTrue(ArchitectureDiff.between(old, old).isEmpty)
    }

    func testWorkspaceDocumentAndContextRetrieval() throws {
        let graph = try Fixtures.graph()
        let ws = Workspace(name: "sample", path: "/tmp/sample")
        let notes = [Note(workspaceID: ws.id, title: "Style", body: "Prefer small functions"), Note(workspaceID: ws.id, title: "Private", body: "secret plan", includeInContext: false)]
        let md = WorkspaceDocument.render(workspace: ws, graph: graph, notes: notes, recentChanges: [(Date(timeIntervalSince1970: 0), "Added pagination")])
        for heading in ["## Project overview", "## Languages and frameworks", "## Architecture summary", "## Important modules", "## Relevant source files",
                        "## Existing APIs", "## Database structure", "## Development constraints", "## User notes", "## Recent verified changes"] {
            XCTAssertTrue(md.contains(heading), "missing \(heading)")
        }
        XCTAssertTrue(md.contains("GET /api/users/:id"))
        XCTAssertFalse(md.contains("secret plan"), "excluded notes stay out of context")

        let ctx = ContextRetriever.retrieve(for: RequestAnalysis("paginate listUsers in the user service"), workspaceName: "sample", graph: graph, notes: notes, recentChanges: [])
        XCTAssertEqual(ctx.components.first?.id, "mod:src/services")
        XCTAssertEqual(ctx.notes, ["Style: Prefer small functions"])
    }
}
