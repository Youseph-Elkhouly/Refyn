import Foundation

public struct Workspace: Codable, Identifiable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var path: String
    public var bookmark: Data?
    public var createdAt: Date
    public var lastOpenedAt: Date
    public var directoryURL: URL { URL(fileURLWithPath: path, isDirectory: true) }

    public init(id: UUID = UUID(), name: String, path: String, bookmark: Data? = nil, createdAt: Date = .now, lastOpenedAt: Date = .now) {
        self.id = id; self.name = name; self.path = path; self.bookmark = bookmark; self.createdAt = createdAt; self.lastOpenedAt = lastOpenedAt
    }

    /// Resolves the security-scoped bookmark when there is one, falling back to the stored path.
    public func resolvedURL() -> URL {
        guard let bookmark else { return directoryURL }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) { return url }
        return directoryURL
    }
}

public struct Note: Codable, Identifiable, Sendable, Hashable {
    public var id: UUID
    public var workspaceID: UUID
    public var title: String
    public var body: String
    public var includeInContext: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), workspaceID: UUID, title: String, body: String = "", includeInContext: Bool = true, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id; self.workspaceID = workspaceID; self.title = title; self.body = body
        self.includeInContext = includeInContext; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct SavedPrompt: Codable, Identifiable, Sendable, Hashable {
    public var id: UUID
    public var workspaceID: UUID
    public var title: String
    public var prompt: String
    public var planID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), workspaceID: UUID, title: String, prompt: String, planID: UUID? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id; self.workspaceID = workspaceID; self.title = title; self.prompt = prompt; self.planID = planID
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

/// One hand-off of a prompt to a coding agent, and what came of it.
public struct ExecutionRecord: Codable, Identifiable, Sendable, Hashable {
    public enum Status: String, Codable, Sendable { case sent, reviewing, confirmed, rejected }

    /// Repository state when the prompt was handed off, so later review isolates changes made after it.
    public struct Baseline: Codable, Hashable, Sendable {
        public var head: String?
        public var fingerprint: String
        public var fileHashes: [String: String]
        /// Paths that already had uncommitted changes at hand-off.
        public var dirtyPaths: [String]
        public var snapshotID: UUID?
        public init(head: String?, fingerprint: String, fileHashes: [String: String], dirtyPaths: [String], snapshotID: UUID?) {
            self.head = head; self.fingerprint = fingerprint; self.fileHashes = fileHashes; self.dirtyPaths = dirtyPaths; self.snapshotID = snapshotID
        }
    }

    public var id: UUID
    public var workspaceID: UUID
    public var planID: UUID?
    public var agent: String
    public var status: Status
    public var baseline: Baseline
    /// Pasted or captured agent output. Supporting context only, never proof.
    public var agentOutput: String
    public var review: ChangeReview?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), workspaceID: UUID, planID: UUID?, agent: String, status: Status = .sent, baseline: Baseline,
                agentOutput: String = "", review: ChangeReview? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id; self.workspaceID = workspaceID; self.planID = planID; self.agent = agent; self.status = status
        self.baseline = baseline; self.agentOutput = agentOutput; self.review = review; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct FileChange: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case added, modified, deleted }
    public var path: String
    public var kind: Kind
    public var additions: Int?
    public var deletions: Int?
    public var patch: String
    public var patchTruncated: Bool
    /// The file already had uncommitted changes before the hand-off; its patch includes them.
    public var hadPriorChanges: Bool
    public var component: String?
    public var id: String { path }

    public init(path: String, kind: Kind, additions: Int? = nil, deletions: Int? = nil, patch: String = "", patchTruncated: Bool = false, hadPriorChanges: Bool = false, component: String? = nil) {
        self.path = path; self.kind = kind; self.additions = additions; self.deletions = deletions; self.patch = patch
        self.patchTruncated = patchTruncated; self.hadPriorChanges = hadPriorChanges; self.component = component
    }
}

/// The result of inspecting the repository after an agent ran.
public struct ChangeReview: Codable, Hashable, Sendable {
    public var files: [FileChange]
    public var architecture: ArchitectureDiff
    public var changedDependencies: [String]
    public var changedTests: [String]
    public var isGitRepository: Bool
    public var headMoved: Bool
    public var reviewedAt: Date
    public var graph: CodebaseGraph

    public init(files: [FileChange], architecture: ArchitectureDiff, changedDependencies: [String], changedTests: [String],
                isGitRepository: Bool, headMoved: Bool, reviewedAt: Date = .now, graph: CodebaseGraph) {
        self.files = files; self.architecture = architecture; self.changedDependencies = changedDependencies
        self.changedTests = changedTests; self.isGitRepository = isGitRepository; self.headMoved = headMoved
        self.reviewedAt = reviewedAt; self.graph = graph
    }
}
