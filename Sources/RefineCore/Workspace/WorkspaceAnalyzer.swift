import Foundation

/// Result of the local, incremental workspace scan used to retrieve prompt context.
public struct AnalysisOutcome: Decodable, Sendable {
    public var graph: CodebaseGraph
}

/// Static analysis only. It never executes repository code and keeps its cache in Refine's support folder.
public actor WorkspaceAnalyzer {
    private let helper: HelperClient
    public init(helper: HelperClient) { self.helper = helper }
    private struct AnalyzeParams: Encodable, Sendable { let root: String; let workspaceId: String; let indexPath: String }

    public func analyze(_ workspace: Workspace) async throws -> AnalysisOutcome {
        let url = workspace.resolvedURL()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let index = AppPaths.workspaceDirectory(workspace.id).appending(path: "file-index.json")
        return try await helper.request("analyze", AnalyzeParams(root: url.path, workspaceId: workspace.id.uuidString, indexPath: index.path), as: AnalysisOutcome.self, timeout: .seconds(600))
    }
}
