import Foundation

/// What an agent integration can observe. Refine only claims a capability when the agent documents
/// an interface for it; everything else falls back to the manual copy → run → review loop.
public struct AgentCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let sessionStart = AgentCapabilities(rawValue: 1 << 0)
    public static let sessionCompletion = AgentCapabilities(rawValue: 1 << 1)
    public static let output = AgentCapabilities(rawValue: 1 << 2)
    public static let toolSummaries = AgentCapabilities(rawValue: 1 << 3)
    public static let changedFiles = AgentCapabilities(rawValue: 1 << 4)
}

public enum AgentEvent: Sendable, Hashable {
    case started(executionID: UUID)
    case completed(executionID: UUID, output: String?)
}

/// An integration with a coding agent. The prompt is always delivered by the user (copy and paste);
/// adapters may additionally report events through interfaces the agent documents.
public protocol AgentAdapter: Sendable {
    var id: String { get }
    var displayName: String { get }
    var capabilities: AgentCapabilities { get }
    /// Text shown after copying, telling the user where to paste.
    var handOffHint: String { get }
    /// Events observed for an execution. Adapters without observable interfaces return an empty stream.
    func events(for execution: ExecutionRecord) -> AsyncStream<AgentEvent>
}

public extension AgentAdapter {
    func events(for execution: ExecutionRecord) -> AsyncStream<AgentEvent> { AsyncStream { $0.finish() } }
}

/// Copy-and-paste hand-off. No events are reported, so none are invented: the user returns to Refine
/// and starts the review, optionally pasting the agent's final message as supporting context.
public struct ManualAgentAdapter: AgentAdapter {
    public let id: String
    public let displayName: String
    public let handOffHint: String
    public var capabilities: AgentCapabilities { [] }
    public init(id: String, displayName: String, handOffHint: String) { self.id = id; self.displayName = displayName; self.handOffHint = handOffHint }
}

public enum AgentRegistry {
    public static let all: [any AgentAdapter] = [
        ManualAgentAdapter(id: "claude-code", displayName: "Claude Code", handOffHint: "Paste into your Claude Code session, then come back and choose Review Changes."),
        ManualAgentAdapter(id: "codex", displayName: "Codex", handOffHint: "Paste into Codex, then come back and choose Review Changes."),
        ManualAgentAdapter(id: "cursor", displayName: "Cursor", handOffHint: "Paste into Cursor's agent, then come back and choose Review Changes."),
        ManualAgentAdapter(id: "t3-code", displayName: "T3 Code", handOffHint: "Paste into T3 Code, then come back and choose Review Changes."),
        ManualAgentAdapter(id: "zed", displayName: "Zed", handOffHint: "Paste into Zed's agent panel, then come back and choose Review Changes."),
        ManualAgentAdapter(id: "other", displayName: "Other agent", handOffHint: "Paste into your agent, then come back and choose Review Changes."),
    ]

    public static func adapter(_ id: String) -> any AgentAdapter { all.first { $0.id == id } ?? all.last! }
}
