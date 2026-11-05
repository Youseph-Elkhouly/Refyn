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

