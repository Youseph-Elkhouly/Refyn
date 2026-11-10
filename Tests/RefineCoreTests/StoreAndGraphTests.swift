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

    func testClarificationAnswerNoteIsVisibleAndIncludedInContext() async throws {
        let ws = try await store.addDirectory(dir)
        let answerText = "Uses PostgreSQL for persistence."
        let note = Note(workspaceID: ws.id, title: "Prompt clarifications · feature", body: "### Which database?\n\n\(answerText)", includeInContext: true)
        try await store.save(note)
        let visible = try await store.notes(workspaceID: ws.id)
        XCTAssertEqual(visible.first?.id, note.id)
        XCTAssertTrue(visible.first?.includeInContext == true)
        let context = ContextRetriever.retrieve(for: RequestAnalysis("add search", confirmedRequirements: [answerText]), workspaceName: ws.name,
                                               graph: nil, notes: visible)
        XCTAssertTrue(context.notes.joined().contains(answerText))
        try await store.deleteNote(note.id)
        let afterDelete = try await store.notes(workspaceID: ws.id)
        XCTAssertFalse(afterDelete.contains { $0.id == note.id })
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

    func testRecentPromptHistoryIncludesWorkspaceAndStandaloneResultsAndSearchesBothTexts() async throws {
        let workspace = try await store.addDirectory(dir)
        let older = PromptPlan(workspaceID: workspace.id, originalPrompt: "Add report export", optimizedPrompt: "Export filtered reports as CSV",
                               createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
        let newer = PromptPlan(originalPrompt: "Fix login timeout", optimizedPrompt: "Reproduce and fix the login timeout", createdAt: Date(timeIntervalSince1970: 200),
                               updatedAt: Date(timeIntervalSince1970: 200))
        try await store.save(older)
        try await store.save(newer)

        let history = try await store.recentPlans()
        let csvMatches = try await store.recentPlans(matching: "CSV")
        let loginMatches = try await store.recentPlans(matching: "login timeout")
        XCTAssertEqual(history.map(\.id), [newer.id, older.id])
        XCTAssertEqual(csvMatches.map(\.id), [older.id])
        XCTAssertEqual(loginMatches.map(\.id), [newer.id])
    }

    func testPromptReoptimizationSavesARevisionWithoutOverwritingThePreviousResult() async throws {
        let previous = PromptPlan(originalPrompt: "Add CSV export", optimizedPrompt: "Export filtered reports as CSV")
        let revision = PromptPlan(revisionOf: previous.id,
                                  originalPrompt: "Add CSV export\n\nAdditional context from you:\nInclude archived reports.",
                                  optimizedPrompt: "Export filtered and archived reports as CSV")
        try await store.save(previous)
        try await store.save(revision)

        let history = try await store.recentPlans(matching: "archived reports")
        XCTAssertEqual(history.map(\.id), [revision.id], "Search should find the new version by its added detail.")
        let fetchedRevision = try await store.plan(revision.id)
        let savedRevision = try XCTUnwrap(fetchedRevision)
        XCTAssertEqual(savedRevision.revisionOf, previous.id)
        let fetchedPrevious = try await store.plan(previous.id)
        XCTAssertNotNil(fetchedPrevious, "The earlier optimized result remains available in history.")
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
        let promptID = UUID()
        try await queue.write { db in
            try db.execute(sql: "INSERT INTO workspaces VALUES (?, 'old', '/tmp/old', NULL, 'remember this', 0, 0)", arguments: [id.uuidString])
            try db.execute(sql: "INSERT INTO savedPrompts VALUES (?, ?, 'Keep me', 'Existing prompt', 0)", arguments: [promptID.uuidString, id.uuidString])
        }
        try queue.close()
        let migrated = try WorkspaceStore(databaseURL: url)
        let notes = try await migrated.notes(workspaceID: id)
        XCTAssertEqual(notes.map(\.body), ["remember this"])
        let saved = try await migrated.savedPrompts(workspaceID: id)
        XCTAssertEqual(saved.map(\.prompt), ["Existing prompt"])
        let migratedQueue = try DatabaseQueue(path: url.path)
        let retainedTables = try await migratedQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }
        XCTAssertTrue(retainedTables.contains("notes"))
        XCTAssertTrue(retainedTables.contains("savedPrompts"))
        XCTAssertFalse(retainedTables.contains("architectureSnapshots"))
        XCTAssertFalse(retainedTables.contains("executionRecords"))
    }

    func testWorkspaceDocumentAndContextRetrieval() throws {
        let graph = try Fixtures.graph()
        let ws = Workspace(name: "sample", path: "/tmp/sample")
        let notes = [Note(workspaceID: ws.id, title: "Style", body: "Prefer small functions"), Note(workspaceID: ws.id, title: "Private", body: "secret plan", includeInContext: false)]
        let md = WorkspaceDocument.render(workspace: ws, graph: graph, notes: notes)
        for heading in ["## Project overview", "## Languages and frameworks", "## Architecture summary", "## Important modules", "## Relevant source files",
                        "## Existing APIs", "## Database structure", "## Development constraints", "## User notes"] {
            XCTAssertTrue(md.contains(heading), "missing \(heading)")
        }
        XCTAssertTrue(md.contains("GET /api/users/:id"))
        XCTAssertFalse(md.contains("secret plan"), "excluded notes stay out of context")

        let ctx = ContextRetriever.retrieve(for: RequestAnalysis("paginate listUsers in the user service"), workspaceName: "sample", graph: graph, notes: notes)
        XCTAssertEqual(ctx.components.first?.id, "mod:src/services")
        XCTAssertEqual(ctx.notes, [], "A note unrelated to the request stays out of the prompt")
        let related = ContextRetriever.retrieve(for: RequestAnalysis("paginate listUsers and prefer small functions"), workspaceName: "sample", graph: graph, notes: notes)
        XCTAssertEqual(related.notes, ["Style: Prefer small functions"])
    }
}
