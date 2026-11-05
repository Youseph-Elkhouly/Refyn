import Foundation

public enum AppPaths {
    /// ~/Library/Application Support/Refyn. The old Refine directory is moved on first launch.
    public static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["REFINE_SUPPORT_DIR"] { return URL(fileURLWithPath: override, isDirectory: true) }
        return migratedSupportDirectory
    }

    private static let migratedSupportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return supportDirectory(at: base)
    }()

    static func supportDirectory(at base: URL, fileManager files: FileManager = .default) -> URL {
        let current = base.appending(path: "Refyn", directoryHint: .isDirectory)
        let previous = base.appending(path: "Refine", directoryHint: .isDirectory)
        if !files.fileExists(atPath: current.path), files.fileExists(atPath: previous.path) {
            do { try files.moveItem(at: previous, to: current) }
            catch { return previous } // Keep using the intact old data if the rename cannot complete.
        }
        return current
    }

    /// Refine-owned analyzer cache for one workspace.
    public static func workspaceDirectory(_ id: UUID) -> URL {
        supportDirectory.appending(path: "Workspaces/\(id.uuidString)", directoryHint: .isDirectory)
    }

    public static var speechModelsDirectory: URL { supportDirectory.appending(path: "SpeechModels", directoryHint: .isDirectory) }
}
