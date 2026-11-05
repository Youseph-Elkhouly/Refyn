import Foundation
import GRDB

public struct Workspace: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var path: String
    public var bookmark: Data?
    public var notes: String
    public var createdAt: Date
    public var lastOpenedAt: Date
    public var directoryURL: URL { URL(fileURLWithPath: path, isDirectory: true) }

    public init(id: UUID = UUID(), name: String, path: String, bookmark: Data? = nil, notes: String = "", createdAt: Date = .now, lastOpenedAt: Date = .now) {
        self.id = id; self.name = name; self.path = path; self.bookmark = bookmark; self.notes = notes; self.createdAt = createdAt; self.lastOpenedAt = lastOpenedAt
    }
}

public struct SavedPrompt: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var workspaceID: UUID
    public var title: String
    public var prompt: String
    public var createdAt: Date
    public init(id: UUID = UUID(), workspaceID: UUID, title: String, prompt: String, createdAt: Date = .now) {
        self.id = id; self.workspaceID = workspaceID; self.title = title; self.prompt = prompt; self.createdAt = createdAt
    }
}

public enum WorkspaceStoreError: Error { case workspaceNotFound }

public actor WorkspaceStore {
    private let database: DatabaseQueue

    public init(databaseURL: URL? = nil) throws {
        let url = databaseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Refine/refine.sqlite")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        database = try DatabaseQueue(path: url.path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("create-workspaces-and-prompts") { db in
            try db.create(table: "workspaces") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("path", .text).notNull().unique()
                table.column("bookmark", .blob)
                table.column("notes", .text).notNull().defaults(to: "")
                table.column("createdAt", .double).notNull()
                table.column("lastOpenedAt", .double).notNull()
            }
            try db.create(table: "savedPrompts") { table in
                table.column("id", .text).primaryKey()
                table.column("workspaceID", .text).notNull().indexed().references("workspaces", onDelete: .cascade)
                table.column("title", .text).notNull()
                table.column("prompt", .text).notNull()
                table.column("createdAt", .double).notNull()
            }
        }
        try migrator.migrate(database)
    }

    public func workspaces() throws -> [Workspace] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM workspaces ORDER BY lastOpenedAt DESC").map(decodeWorkspace)
        }
    }

    public func addDirectory(_ url: URL) throws -> Workspace {
        var bookmark: Data?
        do { bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) }
        catch { bookmark = try? url.bookmarkData() }
        let record = Workspace(name: url.lastPathComponent, path: url.standardizedFileURL.path, bookmark: bookmark)
        try database.write { db in
            try db.execute(sql: "INSERT INTO workspaces (id, name, path, bookmark, notes, createdAt, lastOpenedAt) VALUES (?, ?, ?, ?, ?, ?, ?)", arguments: [record.id.uuidString, record.name, record.path, record.bookmark, record.notes, record.createdAt.timeIntervalSince1970, record.lastOpenedAt.timeIntervalSince1970])
        }
        return record
    }

    public func record(for id: UUID) throws -> Workspace? {
        try database.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM workspaces WHERE id = ?", arguments: [id.uuidString]) else { return nil }
            return try decodeWorkspace(row)
        }
    }

    public func touch(_ id: UUID) throws {
        try database.write { db in try db.execute(sql: "UPDATE workspaces SET lastOpenedAt = ? WHERE id = ?", arguments: [Date.now.timeIntervalSince1970, id.uuidString]) }
    }

    public func rename(_ id: UUID, to name: String) throws {
        try database.write { db in try db.execute(sql: "UPDATE workspaces SET name = ? WHERE id = ?", arguments: [name, id.uuidString]) }
    }

    public func updateNotes(_ id: UUID, notes: String) throws {
        try database.write { db in try db.execute(sql: "UPDATE workspaces SET notes = ? WHERE id = ?", arguments: [notes, id.uuidString]) }
    }

    public func remove(_ id: UUID) throws {
        try database.write { db in try db.execute(sql: "DELETE FROM workspaces WHERE id = ?", arguments: [id.uuidString]) }
    }

    public func save(_ prompt: SavedPrompt) throws {
        try database.write { db in try db.execute(sql: "INSERT OR REPLACE INTO savedPrompts (id, workspaceID, title, prompt, createdAt) VALUES (?, ?, ?, ?, ?)", arguments: [prompt.id.uuidString, prompt.workspaceID.uuidString, prompt.title, prompt.prompt, prompt.createdAt.timeIntervalSince1970]) }
    }

    public func savedPrompts(workspaceID: UUID) throws -> [SavedPrompt] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM savedPrompts WHERE workspaceID = ? ORDER BY createdAt DESC", arguments: [workspaceID.uuidString]).map { row in
                SavedPrompt(id: UUID(uuidString: row["id"]) ?? UUID(), workspaceID: UUID(uuidString: row["workspaceID"]) ?? workspaceID, title: row["title"], prompt: row["prompt"], createdAt: Date(timeIntervalSince1970: row["createdAt"]))
            }
        }
    }

    private func decodeWorkspace(_ row: Row) throws -> Workspace {
        Workspace(id: UUID(uuidString: row["id"]) ?? UUID(), name: row["name"], path: row["path"], bookmark: row["bookmark"], notes: row["notes"], createdAt: Date(timeIntervalSince1970: row["createdAt"]), lastOpenedAt: Date(timeIntervalSince1970: row["lastOpenedAt"]))
    }
}
