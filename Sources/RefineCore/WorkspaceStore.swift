import Foundation
import GRDB

public enum WorkspaceStoreError: Error, LocalizedError {
    case workspaceNotFound
    case duplicateDirectory(String)
    public var errorDescription: String? {
        switch self {
        case .workspaceNotFound: "That workspace no longer exists."
        case .duplicateDirectory(let path): "\(path) is already a workspace."
        }
    }
}

/// All of Refine's local state, in one SQLite database under Application Support.
/// Removing a workspace deletes only Refine's records, never the project directory.
public final class WorkspaceStore: Sendable {
    private let database: DatabaseQueue
    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }()

    public init(databaseURL: URL? = nil) throws {
        let url = databaseURL ?? AppPaths.supportDirectory.appending(path: "refine.sqlite")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = Configuration()
        config.foreignKeysEnabled = true
        database = try DatabaseQueue(path: url.path, configuration: config)
        try Self.migrator.migrate(database)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("create-workspaces-and-prompts") { db in
            try db.create(table: "workspaces") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("path", .text).notNull().unique()
                t.column("bookmark", .blob)
                t.column("notes", .text).notNull().defaults(to: "")
                t.column("createdAt", .double).notNull()
                t.column("lastOpenedAt", .double).notNull()
            }
            try db.create(table: "savedPrompts") { t in
                t.column("id", .text).primaryKey()
                t.column("workspaceID", .text).notNull().indexed().references("workspaces", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("prompt", .text).notNull()
                t.column("createdAt", .double).notNull()
            }
        }
        migrator.registerMigration("v2-notes-plans-architecture-executions") { db in
            try db.alter(table: "savedPrompts") { t in
                t.add(column: "updatedAt", .double).notNull().defaults(to: 0)
                t.add(column: "planID", .text)
            }
            try db.execute(sql: "UPDATE savedPrompts SET updatedAt = createdAt")
            try db.create(table: "notes") { t in
                t.column("id", .text).primaryKey()
                t.column("workspaceID", .text).notNull().indexed().references("workspaces", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("body", .text).notNull()
                t.column("includeInContext", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }
            // The single notes column of v1 becomes the first note.
            let now = Date.now.timeIntervalSince1970
            for row in try Row.fetchAll(db, sql: "SELECT id, notes FROM workspaces WHERE notes != ''") {
                try db.execute(sql: "INSERT INTO notes (id, workspaceID, title, body, includeInContext, createdAt, updatedAt) VALUES (?, ?, 'Notes', ?, 1, ?, ?)",
                               arguments: [UUID().uuidString, row["id"] as String, row["notes"] as String, now, now])
            }
            try db.create(table: "promptPlans") { t in
                t.column("id", .text).primaryKey()
                t.column("workspaceID", .text).indexed().references("workspaces", onDelete: .cascade)
                t.column("cacheKey", .text).indexed()
                t.column("json", .blob).notNull()
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }
        }
        // v3 intentionally removes only Refine's architecture/review history. Workspace,
        // notes, saved prompts, and prompt plans remain untouched on existing databases.
        migrator.registerMigration("v3-remove-architecture-review-history") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS executionRecords")
            try db.execute(sql: "DROP TABLE IF EXISTS architectureSnapshots")
        }
        return migrator
    }

    // MARK: Workspaces

    public func workspaces() async throws -> [Workspace] {
        try await database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM workspaces ORDER BY lastOpenedAt DESC").map(Self.workspace)
        }
    }

    public func workspace(_ id: UUID) async throws -> Workspace? {
        try await database.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM workspaces WHERE id = ?", arguments: [id.uuidString]).map(Self.workspace)
        }
    }

    public func addDirectory(_ url: URL) async throws -> Workspace {
        let path = url.standardizedFileURL.path
        let bookmark = (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)) ?? (try? url.bookmarkData())
        let record = Workspace(name: url.lastPathComponent, path: path, bookmark: bookmark)
        try await database.write { db in
            if try Bool.fetchOne(db, sql: "SELECT 1 FROM workspaces WHERE path = ?", arguments: [path]) == true {
                throw WorkspaceStoreError.duplicateDirectory(path)
            }
            try db.execute(sql: "INSERT INTO workspaces (id, name, path, bookmark, notes, createdAt, lastOpenedAt) VALUES (?, ?, ?, ?, '', ?, ?)",
                           arguments: [record.id.uuidString, record.name, record.path, record.bookmark, record.createdAt.timeIntervalSince1970, record.lastOpenedAt.timeIntervalSince1970])
        }
        return record
    }

    public func touch(_ id: UUID) async throws {
        try await database.write { db in try db.execute(sql: "UPDATE workspaces SET lastOpenedAt = ? WHERE id = ?", arguments: [Date.now.timeIntervalSince1970, id.uuidString]) }
    }

    public func rename(_ id: UUID, to name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await database.write { db in try db.execute(sql: "UPDATE workspaces SET name = ? WHERE id = ?", arguments: [trimmed, id.uuidString]) }
    }

    /// Forgets the workspace and everything Refine stored for it. The project folder is not touched.
    public func remove(_ id: UUID) async throws {
        try await database.write { db in try db.execute(sql: "DELETE FROM workspaces WHERE id = ?", arguments: [id.uuidString]) }
        try? FileManager.default.removeItem(at: AppPaths.workspaceDirectory(id))
    }

    // MARK: Notes

    public func notes(workspaceID: UUID, matching query: String = "") async throws -> [Note] {
        try await database.read { db in
            let like = "%\(query)%"
            return try Row.fetchAll(db, sql: "SELECT * FROM notes WHERE workspaceID = ? AND (? = '' OR title LIKE ? OR body LIKE ?) ORDER BY updatedAt DESC",
                                    arguments: [workspaceID.uuidString, query, like, like]).map { row in
                Note(id: UUID(uuidString: row["id"])!, workspaceID: workspaceID, title: row["title"], body: row["body"],
                     includeInContext: row["includeInContext"], createdAt: Date(timeIntervalSince1970: row["createdAt"]), updatedAt: Date(timeIntervalSince1970: row["updatedAt"]))
            }
        }
    }

    public func save(_ note: Note) async throws {
        try await database.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO notes (id, workspaceID, title, body, includeInContext, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?)",
                           arguments: [note.id.uuidString, note.workspaceID.uuidString, note.title, note.body, note.includeInContext,
                                       note.createdAt.timeIntervalSince1970, note.updatedAt.timeIntervalSince1970])
        }
    }

    public func deleteNote(_ id: UUID) async throws {
        try await database.write { db in try db.execute(sql: "DELETE FROM notes WHERE id = ?", arguments: [id.uuidString]) }
    }

    // MARK: Saved prompts

    public func save(_ prompt: SavedPrompt) async throws {
        try await database.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO savedPrompts (id, workspaceID, title, prompt, createdAt, updatedAt, planID) VALUES (?, ?, ?, ?, ?, ?, ?)",
                           arguments: [prompt.id.uuidString, prompt.workspaceID.uuidString, prompt.title, prompt.prompt,
                                       prompt.createdAt.timeIntervalSince1970, prompt.updatedAt.timeIntervalSince1970, prompt.planID?.uuidString])
        }
    }

    public func savedPrompts(workspaceID: UUID, matching query: String = "") async throws -> [SavedPrompt] {
        try await database.read { db in
            let like = "%\(query)%"
            return try Row.fetchAll(db, sql: "SELECT * FROM savedPrompts WHERE workspaceID = ? AND (? = '' OR title LIKE ? OR prompt LIKE ?) ORDER BY updatedAt DESC",
                                    arguments: [workspaceID.uuidString, query, like, like]).map { row in
                SavedPrompt(id: UUID(uuidString: row["id"])!, workspaceID: workspaceID, title: row["title"], prompt: row["prompt"],
                            planID: (row["planID"] as String?).flatMap(UUID.init(uuidString:)),
                            createdAt: Date(timeIntervalSince1970: row["createdAt"]), updatedAt: Date(timeIntervalSince1970: row["updatedAt"]))
            }
        }
    }

    public func deleteSavedPrompt(_ id: UUID) async throws {
        try await database.write { db in try db.execute(sql: "DELETE FROM savedPrompts WHERE id = ?", arguments: [id.uuidString]) }
    }

    // MARK: Prompt plans

    public func save(_ plan: PromptPlan) async throws {
        let data = try Self.encoder.encode(plan)
        try await database.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO promptPlans (id, workspaceID, cacheKey, json, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?)",
                           arguments: [plan.id.uuidString, plan.workspaceID?.uuidString, plan.cacheKey, data, plan.createdAt.timeIntervalSince1970, plan.updatedAt.timeIntervalSince1970])
        }
    }

    public func plan(_ id: UUID) async throws -> PromptPlan? {
        try await database.read { db in
            try Data.fetchOne(db, sql: "SELECT json FROM promptPlans WHERE id = ?", arguments: [id.uuidString]).map { try Self.decoder.decode(PromptPlan.self, from: $0) }
        }
    }

    /// A previous plan built from exactly the same inputs, so an unchanged request costs no model call.
    public func cachedPlan(cacheKey: String) async throws -> PromptPlan? {
        try await database.read { db in
            try Data.fetchOne(db, sql: "SELECT json FROM promptPlans WHERE cacheKey = ? ORDER BY createdAt DESC LIMIT 1", arguments: [cacheKey])
                .map { try Self.decoder.decode(PromptPlan.self, from: $0) }
        }
    }

    public func plans(workspaceID: UUID, limit: Int = 50) async throws -> [PromptPlan] {
        try await database.read { db in
            try Data.fetchAll(db, sql: "SELECT json FROM promptPlans WHERE workspaceID = ? ORDER BY createdAt DESC LIMIT ?", arguments: [workspaceID.uuidString, limit])
                .map { try Self.decoder.decode(PromptPlan.self, from: $0) }
        }
    }

    /// Recent prompt results across all workspaces, including prompts created without a workspace.
    public func recentPlans(matching query: String = "", limit: Int = 100) async throws -> [PromptPlan] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "%\(trimmed)%"
        return try await database.read { db in
            try Data.fetchAll(db, sql: """
                SELECT json FROM promptPlans
                WHERE (? = '' OR CAST(json AS TEXT) LIKE ? COLLATE NOCASE)
                ORDER BY createdAt DESC LIMIT ?
                """, arguments: [trimmed, pattern, max(1, min(limit, 500))])
                .map { try Self.decoder.decode(PromptPlan.self, from: $0) }
        }
    }

    private static func workspace(_ row: Row) -> Workspace {
        Workspace(id: UUID(uuidString: row["id"]) ?? UUID(), name: row["name"], path: row["path"], bookmark: row["bookmark"],
                  createdAt: Date(timeIntervalSince1970: row["createdAt"]), lastOpenedAt: Date(timeIntervalSince1970: row["lastOpenedAt"]))
    }
}
