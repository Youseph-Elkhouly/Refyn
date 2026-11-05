import Foundation

public struct AnalysisOutcome: Decodable, Sendable {
    public struct Changes: Decodable, Sendable { public var added: [String]; public var modified: [String]; public var removed: [String] }
    public struct Git: Decodable, Sendable { public var isRepository: Bool; public var head: String?; public var dirtyPaths: [String] }
    public var graph: CodebaseGraph
    public var changes: Changes
    public var fileHashes: [String: String]
    public var git: Git
}

public struct DiagramOptions: Encodable, Sendable {
    public struct Removed: Encodable, Sendable { public var id: String; public var name: String; public var type: ComponentType }
    public struct Highlight: Encodable, Sendable {
        public var added: [String] = []
        public var modified: [String] = []
        public var removed: [Removed] = []
        public var addedEdges: [String] = []
        public init() {}
    }
    public struct Planned: Encodable, Sendable { public var id: String; public var name: String; public var type: ComponentType; public var connectsTo: [String] }
    public var title: String?
    public var highlight: Highlight?
    public var planned: [Planned]?
    public var showTests: Bool
    public var dark: Bool

    public init(title: String? = nil, diff: ArchitectureDiff? = nil, planned: [PlannedComponent] = [], showTests: Bool = false, dark: Bool = true) {
        self.title = title
        self.showTests = showTests
        self.dark = dark
        if let diff, !diff.isEmpty {
            var h = Highlight()
            h.added = diff.addedNodes.map(\.id)
            h.modified = diff.modifiedNodes.map(\.id)
            h.removed = diff.removedNodes.map { Removed(id: $0.id, name: $0.name, type: $0.type) }
            h.addedEdges = diff.addedEdges.map(\.id)
            highlight = h
        }
        self.planned = planned.isEmpty ? nil : planned.map { Planned(id: $0.id, name: $0.name, type: $0.type, connectsTo: $0.connectsTo) }
    }
}

public struct DiagramResult: Decodable, Sendable {
    public var svg: String
    /// Diagram element id → graph node id.
    public var elementIds: [String: String]
    public var hidden: Int
    public var warnings: [String]
}

struct FileDiff: Decodable, Sendable {
    var path: String
    var additions: Int?
    var deletions: Int?
    var patch: String
    var truncated: Bool
}

/// Static analysis, snapshots, change review and diagrams for workspaces. Talks to RefineHelper for the
/// parsing, git and Giotto work; owns persistence and the verified/unverified distinction.
public actor ArchitectureService {
    let helper: HelperClient
    let store: WorkspaceStore

    public init(helper: HelperClient, store: WorkspaceStore) {
        self.helper = helper
        self.store = store
    }

    private struct AnalyzeParams: Encodable, Sendable { let root: String; let workspaceId: String; let indexPath: String }
    private struct DiffParams: Encodable, Sendable { let root: String; let base: String?; let paths: [String] }
    private struct RenderParams: Encodable, Sendable { let graph: CodebaseGraph; let options: DiagramOptions }
    private struct DiffResponse: Decodable, Sendable { let files: [FileDiff] }

    /// Incremental scan: unchanged files are not re-read or re-parsed (the helper keeps a per-workspace file index).
    public func analyze(_ workspace: Workspace) async throws -> AnalysisOutcome {
        let url = workspace.resolvedURL()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let index = AppPaths.workspaceDirectory(workspace.id).appending(path: "file-index.json")
        return try await helper.request("analyze", AnalyzeParams(root: url.path, workspaceId: workspace.id.uuidString, indexPath: index.path), as: AnalysisOutcome.self, timeout: .seconds(600))
    }

    /// Scans and stores a new verified snapshot when the code differs from the last verified one.
    @discardableResult
    public func scan(_ workspace: Workspace, label: String = "Workspace scan") async throws -> ArchitectureSnapshot {
        let outcome = try await analyze(workspace)
        let previous = try await store.latestSnapshot(workspaceID: workspace.id)
        if let previous, previous.fingerprint == outcome.graph.metadata.snapshot.fingerprint { return previous }
        let diff = previous.map { ArchitectureDiff.between($0.graph, outcome.graph) }
        let snapshot = try await store.appendSnapshot(ArchitectureSnapshot(workspaceID: workspace.id, version: 0, label: label, verified: true, graph: outcome.graph, diff: diff))
        try await regenerateContext(workspace)
        return snapshot
    }

    /// Records the repository state at hand-off so a later review only attributes changes made after it.
    public func beginExecution(workspace: Workspace, planID: UUID?, agent: String) async throws -> ExecutionRecord {
        let outcome = try await analyze(workspace)
        let verified = try await store.latestSnapshot(workspaceID: workspace.id)
        let baseline = ExecutionRecord.Baseline(head: outcome.git.head, fingerprint: outcome.graph.metadata.snapshot.fingerprint,
                                                fileHashes: outcome.fileHashes, dirtyPaths: outcome.git.dirtyPaths, snapshotID: verified?.id)
        let record = ExecutionRecord(workspaceID: workspace.id, planID: planID, agent: agent, baseline: baseline)
        try await store.save(record)
        return record
    }

    /// Inspects what changed since the hand-off. The repository is the source of truth; agent output is not consulted.
    public func review(_ record: ExecutionRecord, workspace: Workspace) async throws -> ChangeReview {
        let outcome = try await analyze(workspace)
        let before = record.baseline.fileHashes, after = outcome.fileHashes
        var changes: [(String, FileChange.Kind)] = []
        for (path, hash) in after where before[path] != hash { changes.append((path, before[path] == nil ? .added : .modified)) }
        for path in before.keys where after[path] == nil { changes.append((path, .deleted)) }
        changes.sort { $0.0 < $1.0 }

        var diffs: [String: FileDiff] = [:]
        if outcome.git.isRepository, !changes.isEmpty {
            let url = workspace.resolvedURL()
            let response = try await helper.request("git.diff", DiffParams(root: url.path, base: record.baseline.head, paths: changes.map(\.0)), as: DiffResponse.self)
            diffs = Dictionary(response.files.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        }
        let dirty = Set(record.baseline.dirtyPaths)
        var baselineGraph: CodebaseGraph?
        if let id = record.baseline.snapshotID { baselineGraph = try await store.snapshot(id)?.graph }
        let files = changes.map { path, kind in
            let d = diffs[path]
            return FileChange(path: path, kind: kind, additions: d?.additions, deletions: d?.deletions, patch: d?.patch ?? "", patchTruncated: d?.truncated ?? false,
                              hadPriorChanges: dirty.contains(path), component: (outcome.graph.node(containing: path) ?? baselineGraph?.node(containing: path))?.name)
        }
        let manifests = #/(^|/)(package\.json|Package\.swift|Package\.resolved|requirements[^/]*\.txt|pyproject\.toml|Podfile|go\.mod|Cargo\.toml|Gemfile)$/#
        let tests = #/(^|/)(tests?|__tests__|spec|Tests)/|\.(test|spec)\.[jt]sx?$|_test\.py$|Tests?\.swift$/#
        return ChangeReview(
            files: files,
            architecture: ArchitectureDiff.between(baselineGraph, outcome.graph),
            changedDependencies: files.map(\.path).filter { $0.contains(manifests) },
            changedTests: files.map(\.path).filter { $0.contains(tests) },
            isGitRepository: outcome.git.isRepository,
            headMoved: outcome.git.head != record.baseline.head,
            graph: outcome.graph)
    }

    /// The user accepted the result: the reviewed graph becomes the verified architecture.
    public func confirm(_ record: ExecutionRecord, review: ChangeReview, workspace: Workspace, label: String) async throws -> ArchitectureSnapshot {
        var r = record
        r.status = .confirmed
        r.review = review
        r.updatedAt = .now
        try await store.save(r)
        let previous = try await store.latestSnapshot(workspaceID: workspace.id)
        let snapshot = try await store.appendSnapshot(ArchitectureSnapshot(
            workspaceID: workspace.id, version: 0, label: label, verified: true, graph: review.graph,
            diff: ArchitectureDiff.between(previous?.graph, review.graph), executionID: record.id))
        try await regenerateContext(workspace)
        return snapshot
    }

    /// The user rejected the result: the verified architecture stays as it was. The observed state is kept, unverified, for history.
    public func reject(_ record: ExecutionRecord, review: ChangeReview?, workspace: Workspace, label: String) async throws {
        var r = record
        r.status = .rejected
        r.review = review
        r.updatedAt = .now
        try await store.save(r)
        if let review {
            let previous = try await store.latestSnapshot(workspaceID: workspace.id)
            _ = try await store.appendSnapshot(ArchitectureSnapshot(
                workspaceID: workspace.id, version: 0, label: "Rejected: \(label)", verified: false, graph: review.graph,
                diff: ArchitectureDiff.between(previous?.graph, review.graph), executionID: record.id))
        }
    }

    public func render(_ graph: CodebaseGraph, options: DiagramOptions) async throws -> DiagramResult {
        try await helper.request("diagram.render", RenderParams(graph: graph, options: options), as: DiagramResult.self, timeout: .seconds(60))
    }

    /// Rewrites workspace.md from the latest verified graph, notes and confirmed changes.
    @discardableResult
    public func regenerateContext(_ workspace: Workspace) async throws -> URL {
        let snapshot = try await store.latestSnapshot(workspaceID: workspace.id)
        let notes = try await store.notes(workspaceID: workspace.id)
        let changes = try await recentVerifiedChanges(workspace.id)
        let md = WorkspaceDocument.render(workspace: workspace, graph: snapshot?.graph, notes: notes, recentChanges: changes)
        return try WorkspaceDocument.write(md, workspaceID: workspace.id)
    }

    public func recentVerifiedChanges(_ workspaceID: UUID) async throws -> [(date: Date, summary: String)] {
        let records = try await store.executions(workspaceID: workspaceID).filter { $0.status == .confirmed }
        var out: [(Date, String)] = []
        for r in records.prefix(10) {
            var intent: String?
            if let planID = r.planID { intent = try await store.plan(planID)?.intent }
            let files = r.review?.files.count ?? 0
            out.append((r.updatedAt, "\(intent ?? "Agent change") — \(files) file(s) changed"))
        }
        return out
    }
}
