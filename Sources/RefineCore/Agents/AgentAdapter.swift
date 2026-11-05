/// Agent destinations shown next to generated prompts; hand-off remains copy and paste.
public struct ManualAgentAdapter: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public init(id: String, displayName: String) { self.id = id; self.displayName = displayName }
}

public enum AgentRegistry {
    public static let all: [ManualAgentAdapter] = [
        ManualAgentAdapter(id: "claude-code", displayName: "Claude Code"),
        ManualAgentAdapter(id: "codex", displayName: "Codex"),
        ManualAgentAdapter(id: "cursor", displayName: "Cursor"),
        ManualAgentAdapter(id: "t3-code", displayName: "T3 Code"),
        ManualAgentAdapter(id: "zed", displayName: "Zed"),
        ManualAgentAdapter(id: "other", displayName: "Other agent"),
    ]

    public static func adapter(_ id: String) -> ManualAgentAdapter { all.first { $0.id == id } ?? all.last! }
}
