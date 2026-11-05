import Foundation

public enum AppPaths {
    /// ~/Library/Application Support/Refine, or $REFINE_SUPPORT_DIR (used by tests).
    public static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["REFINE_SUPPORT_DIR"] { return URL(fileURLWithPath: override, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Refine", directoryHint: .isDirectory)
    }

    /// Generated metadata for one workspace: workspace.md and the analyzer's file index.
    public static func workspaceDirectory(_ id: UUID) -> URL {
        supportDirectory.appending(path: "Workspaces/\(id.uuidString)", directoryHint: .isDirectory)
    }

    public static var speechModelsDirectory: URL { supportDirectory.appending(path: "SpeechModels", directoryHint: .isDirectory) }
}
