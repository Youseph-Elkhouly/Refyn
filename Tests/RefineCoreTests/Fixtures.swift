import Foundation
@testable import RefineCore

enum Fixtures {
    static let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let sampleApp = repoRoot.appending(path: "RefineHelper/test/fixtures/sample-app")

    static func graph(nodes: [GraphNode]? = nil, edges: [GraphEdge]? = nil) throws -> CodebaseGraph {
        let meta = GraphMetadata(workspaceId: "w", analyzedAt: "2026-11-05T00:00:00Z",
                                 snapshot: .init(head: "abc", branch: "main", dirty: false, fingerprint: "f1"),
                                 supportedLanguages: [.init(name: "TypeScript", level: "syntax")],
                                 languages: [.init(name: "TypeScript", files: 4, analyzed: true)],
                                 frameworks: [.init(name: "Express", evidence: SourceRef(path: "package.json"))],
                                 entryPoints: [SourceRef(path: "src/server/index.ts")], warnings: [],
                                 stats: .init(files: 4, reparsed: 4, reused: 0, skipped: 0))
        return CodebaseGraph(schemaVersion: 1, metadata: meta, nodes: nodes ?? [
            GraphNode(id: "mod:src/server", name: "src/server", type: .api, path: "src/server", group: "API", files: ["src/server/index.ts"],
                      routes: [GraphRoute(method: "GET", path: "/api/users/:id", source: SourceRef(path: "src/server/index.ts", line: 5))]),
            GraphNode(id: "mod:src/services", name: "src/services", type: .service, path: "src/services", group: "Services", files: ["src/services/users.ts"],
                      symbols: [GraphSymbol(name: "listUsers", kind: "function", path: "src/services/users.ts", line: 3)]),
        ], edges: edges ?? [
            GraphEdge(source: "mod:src/server", target: "mod:src/services", relation: "imports", evidence: [SourceRef(path: "src/server/index.ts", line: 2)], verification: .confirmed),
        ])
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "refine-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
