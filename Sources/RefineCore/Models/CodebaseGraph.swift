import Foundation

// Mirrors SharedSchemas/codebase-graph.schema.json, produced by RefineHelper.

public enum Verification: String, Codable, Sendable {
    /// Traceable to source evidence found by static analysis.
    case confirmed
    /// Derived heuristically (a name or URL string match), not proven.
    case inferred
    case unknown
}

public enum ComponentType: String, Codable, CaseIterable, Sendable {
    case frontend, api, service, database, entry, library, test, config, external
}

public struct SourceRef: Codable, Hashable, Sendable {
    public var path: String
    public var line: Int?
    public var detail: String?
    public init(path: String, line: Int? = nil, detail: String? = nil) { self.path = path; self.line = line; self.detail = detail }
    public var display: String { line.map { "\(path):\($0)" } ?? path }
}

public struct GraphSymbol: Codable, Hashable, Sendable {
    public var name: String
    public var kind: String
    public var path: String
    public var line: Int
    public init(name: String, kind: String, path: String, line: Int) { self.name = name; self.kind = kind; self.path = path; self.line = line }
}

public struct GraphRoute: Codable, Hashable, Sendable {
    public var method: String
    public var path: String
    public var source: SourceRef
}

public struct GraphNode: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var type: ComponentType
    public var path: String
    public var group: String
    public var files: [String]
    public var languages: [String]
    public var symbols: [GraphSymbol]
    public var routes: [GraphRoute]
    public var evidence: [SourceRef]
    public var verification: Verification

    public init(id: String, name: String, type: ComponentType, path: String, group: String = "", files: [String] = [], languages: [String] = [],
                symbols: [GraphSymbol] = [], routes: [GraphRoute] = [], evidence: [SourceRef] = [], verification: Verification = .confirmed) {
        self.id = id; self.name = name; self.type = type; self.path = path; self.group = group; self.files = files
        self.languages = languages; self.symbols = symbols; self.routes = routes; self.evidence = evidence; self.verification = verification
    }
}

public struct GraphEdge: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var source: String
    public var target: String
    public var relation: String
    public var evidence: [SourceRef]
    public var verification: Verification

    public init(id: String? = nil, source: String, target: String, relation: String, evidence: [SourceRef] = [], verification: Verification) {
        self.id = id ?? "\(source)->\(target):\(relation)"; self.source = source; self.target = target
        self.relation = relation; self.evidence = evidence; self.verification = verification
    }
}

public struct GraphMetadata: Codable, Hashable, Sendable {
    public struct Snapshot: Codable, Hashable, Sendable {
        public var head: String?
        public var branch: String?
        public var dirty: Bool
        public var fingerprint: String
    }
    public struct Language: Codable, Hashable, Sendable {
        public var name: String
        public var files: Int
        public var analyzed: Bool
    }
    public struct SupportedLanguage: Codable, Hashable, Sendable {
        public var name: String
        public var level: String
    }
    public struct Framework: Codable, Hashable, Sendable {
        public var name: String
        public var evidence: SourceRef
    }
    public struct Stats: Codable, Hashable, Sendable {
        public var files: Int
        public var reparsed: Int
        public var reused: Int
        public var skipped: Int
    }
    public var workspaceId: String
    public var analyzedAt: String
    public var snapshot: Snapshot
    public var supportedLanguages: [SupportedLanguage]
    public var languages: [Language]
    public var frameworks: [Framework]
    public var entryPoints: [SourceRef]
    public var warnings: [String]
    public var stats: Stats
}

public struct CodebaseGraph: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var metadata: GraphMetadata
    public var nodes: [GraphNode]
    public var edges: [GraphEdge]

    public func node(_ id: String) -> GraphNode? { nodes.first { $0.id == id } }
    public func edges(touching id: String) -> [GraphEdge] { edges.filter { $0.source == id || $0.target == id } }
    /// The component that owns a file, if any.
    public func node(containing path: String) -> GraphNode? { nodes.first { $0.files.contains(path) } }
}

/// What changed between two graphs.
public struct ArchitectureDiff: Codable, Hashable, Sendable {
    public struct Modified: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var addedFiles: [String]
        public var removedFiles: [String]
        public var addedSymbols: [String]
        public var removedSymbols: [String]
        public var addedRoutes: [String]
        public var removedRoutes: [String]
    }
    public var addedNodes: [GraphNode]
    public var removedNodes: [GraphNode]
    public var modifiedNodes: [Modified]
    public var addedEdges: [GraphEdge]
    public var removedEdges: [GraphEdge]
    /// Added relationships that are not backed by confirmed evidence.
    public var unverifiedEdges: [GraphEdge]

    public var isEmpty: Bool { addedNodes.isEmpty && removedNodes.isEmpty && modifiedNodes.isEmpty && addedEdges.isEmpty && removedEdges.isEmpty }

    public static func between(_ old: CodebaseGraph?, _ new: CodebaseGraph) -> ArchitectureDiff {
        let oldNodes = Dictionary((old?.nodes ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newNodes = Dictionary(new.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let oldEdges = Set((old?.edges ?? []).map(\.id))
        let newEdges = Set(new.edges.map(\.id))
        var modified: [Modified] = []
        for node in new.nodes {
            guard let before = oldNodes[node.id] else { continue }
            let sym = { (n: GraphNode) in Set(n.symbols.map { "\($0.kind) \($0.name)" }) }
            let routes = { (n: GraphNode) in Set(n.routes.map { "\($0.method) \($0.path)" }) }
            let m = Modified(id: node.id, name: node.name,
                             addedFiles: Set(node.files).subtracting(before.files).sorted(),
                             removedFiles: Set(before.files).subtracting(node.files).sorted(),
                             addedSymbols: sym(node).subtracting(sym(before)).sorted(),
                             removedSymbols: sym(before).subtracting(sym(node)).sorted(),
                             addedRoutes: routes(node).subtracting(routes(before)).sorted(),
                             removedRoutes: routes(before).subtracting(routes(node)).sorted())
            if !(m.addedFiles.isEmpty && m.removedFiles.isEmpty && m.addedSymbols.isEmpty && m.removedSymbols.isEmpty && m.addedRoutes.isEmpty && m.removedRoutes.isEmpty) {
                modified.append(m)
            }
        }
        let added = new.edges.filter { !oldEdges.contains($0.id) }
        return ArchitectureDiff(
            addedNodes: new.nodes.filter { oldNodes[$0.id] == nil },
            removedNodes: (old?.nodes ?? []).filter { newNodes[$0.id] == nil },
            modifiedNodes: modified,
            addedEdges: added,
            removedEdges: (old?.edges ?? []).filter { !newEdges.contains($0.id) },
            unverifiedEdges: added.filter { $0.verification != .confirmed })
    }
}

public struct ArchitectureSnapshot: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var workspaceID: UUID
    public var version: Int
    public var label: String
    /// True once the user accepted it (initial scans and confirmed reviews).
    public var verified: Bool
    public var head: String?
    public var fingerprint: String
    public var graph: CodebaseGraph
    /// Difference from the previous verified snapshot.
    public var diff: ArchitectureDiff?
    public var executionID: UUID?
    public var createdAt: Date

    public init(id: UUID = UUID(), workspaceID: UUID, version: Int, label: String, verified: Bool, graph: CodebaseGraph,
                diff: ArchitectureDiff? = nil, executionID: UUID? = nil, createdAt: Date = .now) {
        self.id = id; self.workspaceID = workspaceID; self.version = version; self.label = label; self.verified = verified
        self.head = graph.metadata.snapshot.head; self.fingerprint = graph.metadata.snapshot.fingerprint
        self.graph = graph; self.diff = diff; self.executionID = executionID; self.createdAt = createdAt
    }
}
