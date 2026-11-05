import XCTest
@testable import RefineCore

/// Runs the real Node helper against a copy of the sample app. Requires Node.js 20+ and `npm run build` in RefineHelper.
final class ArchitectureIntegrationTests: XCTestCase {
    var dir: URL!
    var project: URL!
    var helper: HelperClient!
    var store: WorkspaceStore!
    var service: ArchitectureService!

    override func setUp() async throws {
        let script = Fixtures.repoRoot.appending(path: "RefineHelper/dist/src/main.js")
        guard FileManager.default.fileExists(atPath: script.path), (try? HelperClient.locateNode(override: nil)) != nil else {
            throw XCTSkip("Node.js or the built helper is unavailable")
        }
        dir = try Fixtures.temporaryDirectory()
        setenv("REFINE_SUPPORT_DIR", dir.appending(path: "support").path, 1)
        project = dir.appending(path: "sample-app")
        try FileManager.default.copyItem(at: Fixtures.sampleApp, to: project)
        try git("init", "-q")
        try git("add", "-A")
        try git("-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-qm", "init")
        helper = HelperClient(helperScript: script, idleTimeout: .seconds(5))
        store = try WorkspaceStore(databaseURL: dir.appending(path: "refine.sqlite"))
        service = ArchitectureService(helper: helper, store: store)
    }

    override func tearDown() async throws {
        await helper?.stop()
        unsetenv("REFINE_SUPPORT_DIR")
        if let dir { try? FileManager.default.removeItem(at: dir) }
    }

    func git(_ args: String...) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", project.path] + args
        p.standardOutput = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw NSError(domain: "git", code: Int(p.terminationStatus)) }
    }

    func testScanReviewConfirmAndRender() async throws {
        let ws = try await store.addDirectory(project)
        let first = try await service.scan(ws)
        XCTAssertEqual(first.version, 1)
        XCTAssertTrue(first.verified)
        XCTAssertNotNil(first.graph.node("mod:src/services"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: AppPaths.workspaceDirectory(ws.id).appending(path: "workspace.md").path))

        // A rescan with no changes reuses every file and creates no new version.
        let again = try await service.scan(ws)
        XCTAssertEqual(again.id, first.id)

        // A change made before the hand-off must not be attributed to the agent.
        try "// unrelated local edit\n".write(to: project.appending(path: "src/db/notes.ts"), atomically: true, encoding: .utf8)
        let record = try await service.beginExecution(workspace: ws, planID: nil, agent: "claude-code")
        XCTAssertTrue(record.baseline.dirtyPaths.contains("src/db/notes.ts"))

        // The "agent" adds a billing service that uses the database and edits the users service.
        try "import { db } from '../db/client';\nexport class BillingService { charge() { return db; } }\n"
            .write(to: project.appending(path: "src/services/billing.ts"), atomically: true, encoding: .utf8)
        let users = project.appending(path: "src/services/users.ts")
        try (String(contentsOf: users, encoding: .utf8) + "\nexport function countUsers() { return 0; }\n").write(to: users, atomically: true, encoding: .utf8)

        let review = try await service.review(record, workspace: ws)
        XCTAssertEqual(review.files.map(\.path), ["src/services/billing.ts", "src/services/users.ts"])
        XCTAssertEqual(review.files.map(\.kind), [.added, .modified])
        XCTAssertEqual(review.files[1].additions, 2)
        XCTAssertTrue(review.files[1].patch.contains("+export function countUsers"))
        XCTAssertTrue(review.isGitRepository)
        let modified = try XCTUnwrap(review.architecture.modifiedNodes.first { $0.id == "mod:src/services" })
        XCTAssertTrue(modified.addedSymbols.contains("function countUsers"))
        XCTAssertTrue(modified.addedSymbols.contains("class BillingService"))

        let confirmed = try await service.confirm(record, review: review, workspace: ws, label: "Add billing")
        XCTAssertEqual(confirmed.version, 2)
        XCTAssertEqual(confirmed.executionID, record.id)
        let executions = try await store.executions(workspaceID: ws.id)
        XCTAssertEqual(executions.first?.status, .confirmed)
        let md = try String(contentsOf: AppPaths.workspaceDirectory(ws.id).appending(path: "workspace.md"), encoding: .utf8)
        XCTAssertTrue(md.contains("BillingService"))

        let diagram = try await service.render(confirmed.graph, options: DiagramOptions(diff: confirmed.diff, planned: [PlannedComponent(id: "p1", name: "Invoices", type: .service, connectsTo: ["mod:src/services"])]))
        XCTAssertTrue(diagram.svg.hasPrefix("<svg"))
        XCTAssertTrue(diagram.elementIds.values.contains("mod:src/services"))
        XCTAssertNil(confirmed.graph.nodes.first { $0.name == "Invoices" }, "planned components never enter the verified graph")
    }

    func testRejectKeepsVerifiedArchitecture() async throws {
        let ws = try await store.addDirectory(project)
        let first = try await service.scan(ws)
        let record = try await service.beginExecution(workspace: ws, planID: nil, agent: "codex")
        try "export const x = 1;\n".write(to: project.appending(path: "src/services/extra.ts"), atomically: true, encoding: .utf8)
        let review = try await service.review(record, workspace: ws)
        try await service.reject(record, review: review, workspace: ws, label: "Extra")
        let verified = try await store.latestSnapshot(workspaceID: ws.id)
        XCTAssertEqual(verified?.id, first.id)
        let latest = try await store.latestSnapshot(workspaceID: ws.id, verifiedOnly: false)
        XCTAssertEqual(latest?.verified, false)
    }

    func testHelperRestartsAfterStop() async throws {
        let ws = try await store.addDirectory(project)
        _ = try await service.analyze(ws)
        await helper.stop()
        let running = await helper.isRunning
        XCTAssertFalse(running)
        _ = try await service.analyze(ws)
        let runningAgain = await helper.isRunning
        XCTAssertTrue(runningAgain)
    }
}
