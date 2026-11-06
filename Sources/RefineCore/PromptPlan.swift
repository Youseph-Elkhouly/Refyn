import Foundation

public enum PromptMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto = "Auto"
    case basic = "Basic"
    case advanced = "Advanced"
    case custom = "Custom"
    public var id: String { rawValue }
}

public enum TaskType: String, Codable, CaseIterable, Sendable {
    case feature, bugfix, refactor, test, docs, performance, ui, investigation, config, other
}

/// Techniques the optimizer can apply. Each one changes what the generated prompt asks of the coding agent.
public enum PromptTechnique: String, Codable, CaseIterable, Identifiable, Sendable {
    case zeroShot = "Zero-shot"
    case role = "Role prompting"
    case contextInjection = "Context injection"
    case structured = "Structured instructions"
    case outputFormat = "Output formatting"
    case constraints = "Constraint specification"
    case fewShot = "Few-shot examples"
    case decomposition = "Task decomposition"
    case promptChaining = "Prompt chaining"
    case selfCritique = "Self-critique and revision"
    case boundedIteration = "Bounded iterative loop"
    case conditionalBranching = "Conditional branching"
    case verification = "Verification-driven"
    case toolUse = "ReAct-style tool use"
    case multiStage = "Multi-stage workflow"
    case dependencyPlanning = "Dependency-aware planning"
    case acceptanceCriteria = "Acceptance criteria"

    public var id: String { rawValue }

    /// Plain-language names used in the Custom mode picker.
    public var displayTitle: String {
        switch self {
        case .zeroShot: "Keep it simple"
        case .role: "Set a role"
        case .contextInjection: "Use project details"
        case .structured: "Organize the request"
        case .outputFormat: "Choose a response format"
        case .constraints: "Protect what should stay the same"
        case .fewShot: "Show an example"
        case .decomposition: "Break the work into steps"
        case .promptChaining: "Split work into separate prompts"
        case .selfCritique: "Review before finishing"
        case .boundedIteration: "Allow a few fix-and-check rounds"
        case .conditionalBranching: "Add if/then guidance"
        case .verification: "Ask it to run checks"
        case .toolUse: "Guide how it uses tools"
        case .multiStage: "Use inspect, change, and check stages"
        case .dependencyPlanning: "Put tasks in the right order"
        case .acceptanceCriteria: "Define when the work is done"
        }
    }

    /// Short explanation shown beside the plain-language name in Custom mode.
    public var userDescription: String {
        switch self {
        case .zeroShot: "Use a direct instruction without extra structure."
        case .role: "Give the coding assistant a useful point of view."
        case .contextInjection: "Include relevant files, frameworks, and workspace notes."
        case .structured: "Separate the goal, requirements, and suggestions."
        case .outputFormat: "Ask for a clear report of the result."
        case .constraints: "Call out what must not change."
        case .fewShot: "Show the kind of result you want."
        case .decomposition: "Turn a large request into manageable actions."
        case .promptChaining: "Create smaller prompts to run one after another."
        case .selfCritique: "Have the assistant review its changes before it finishes."
        case .boundedIteration: "Let it test and fix problems for a limited number of rounds."
        case .conditionalBranching: "Say what to do when something differs from expectations."
        case .verification: "Include specific checks for the assistant to run."
        case .toolUse: "Give tool-using assistants a clear search, edit, and check process."
        case .multiStage: "Work through inspect, change, and verify stages."
        case .dependencyPlanning: "Do prerequisite work before dependent tasks."
        case .acceptanceCriteria: "List observable signs that the request is complete."
        }
    }

    public var isAdvanced: Bool {
        switch self {
        case .zeroShot, .role, .contextInjection, .structured, .outputFormat, .constraints, .fewShot: false
        default: true
        }
    }

    public var summary: String {
        switch self {
        case .zeroShot: "A direct, clarified instruction with no scaffolding."
        case .role: "Frames the agent's role for this codebase."
        case .contextInjection: "Adds relevant files, modules and notes from the workspace."
        case .structured: "Separates objective, requirements and suggestions."
        case .outputFormat: "Specifies what the agent reports back."
        case .constraints: "States what must not change."
        case .fewShot: "Shows an example of the expected report."
        case .decomposition: "Breaks the work into tasks."
        case .promptChaining: "Splits the work into prompts run one after another."
        case .selfCritique: "Has the agent review its own diff before finishing."
        case .boundedIteration: "Implement, test, fix — up to a fixed number of attempts."
        case .conditionalBranching: "Says what to do when the code differs from expectations."
        case .verification: "Defines checks the agent must run."
        case .toolUse: "Search, read, act, observe — for agents with tools."
        case .multiStage: "Inspect, implement, verify and report as stages."
        case .dependencyPlanning: "Orders tasks by their dependencies."
        case .acceptanceCriteria: "Lists explicit, checkable done conditions."
        }
    }
}

public struct PlanTask: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var dependsOn: [String]
    public init(id: String, title: String, detail: String = "", dependsOn: [String] = []) {
        self.id = id; self.title = title; self.detail = detail; self.dependsOn = dependsOn
    }
}

public struct CodeReference: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable { case graph, model }
    public var path: String
    public var symbol: String?
    public var reason: String
    public var source: Source
    public init(path: String, symbol: String? = nil, reason: String, source: Source) {
        self.path = path; self.symbol = symbol; self.reason = reason; self.source = source
    }
}

/// A component the request would add. Shown only as a planned overlay, never as part of the codebase.
public struct PlannedComponent: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var type: ComponentType
    public var connectsTo: [String]
    public init(id: String, name: String, type: ComponentType, connectsTo: [String] = []) {
        self.id = id; self.name = name; self.type = type; self.connectsTo = connectsTo
    }
}

public struct IntentValidation: Codable, Hashable, Sendable {
    /// Terms from the original request (identifiers, paths, quoted text) missing from the generated prompt before repair.
    public var missingTerms: [String]
    public var modelReportedPreserved: Bool?
    public var repaired: Bool
    public var passed: Bool { missingTerms.isEmpty && modelReportedPreserved != false }
    public init(missingTerms: [String] = [], modelReportedPreserved: Bool? = nil, repaired: Bool = false) {
        self.missingTerms = missingTerms; self.modelReportedPreserved = modelReportedPreserved; self.repaired = repaired
    }
}

/// What the user wants the coding agent to do. Not a description of the existing codebase (see `CodebaseGraph`).
public struct PromptPlan: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var workspaceID: UUID?
    public var originalPrompt: String
    public var optimizedPrompt: String
    /// Sequential prompts when prompt chaining is selected; empty otherwise.
    public var chainedPrompts: [String]
    public var mode: PromptMode
    public var intent: String
    public var taskType: TaskType
    public var selectedTechniques: [PromptTechnique]
    public var codeReferences: [CodeReference]
    public var tasks: [PlanTask]
    public var constraints: [String]
    public var successCriteria: [String]
    public var missingInformation: [String]
    /// Stated by the user in the request.
    public var confirmedRequirements: [String]
    /// Proposed by the optimizer; the agent may revise them.
    public var suggestedDecisions: [String]
    public var plannedComponents: [PlannedComponent]
    public var iterationLimit: Int
    public var verificationInstructions: [String]
    public var validation: IntentValidation
    /// "local" when built without a model call.
    public var provider: String
    public var notices: [String]
    public var cacheKey: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), workspaceID: UUID? = nil, originalPrompt: String, optimizedPrompt: String = "", chainedPrompts: [String] = [],
                mode: PromptMode = .auto, intent: String = "", taskType: TaskType = .other, selectedTechniques: [PromptTechnique] = [],
                codeReferences: [CodeReference] = [], tasks: [PlanTask] = [], constraints: [String] = [], successCriteria: [String] = [],
                missingInformation: [String] = [], confirmedRequirements: [String] = [], suggestedDecisions: [String] = [],
                plannedComponents: [PlannedComponent] = [], iterationLimit: Int = 0, verificationInstructions: [String] = [],
                validation: IntentValidation = IntentValidation(), provider: String = "local", notices: [String] = [], cacheKey: String = "",
                createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id; self.workspaceID = workspaceID; self.originalPrompt = originalPrompt; self.optimizedPrompt = optimizedPrompt
        self.chainedPrompts = chainedPrompts; self.mode = mode; self.intent = intent; self.taskType = taskType
        self.selectedTechniques = selectedTechniques; self.codeReferences = codeReferences; self.tasks = tasks
        self.constraints = constraints; self.successCriteria = successCriteria; self.missingInformation = missingInformation
        self.confirmedRequirements = confirmedRequirements; self.suggestedDecisions = suggestedDecisions
        self.plannedComponents = plannedComponents; self.iterationLimit = iterationLimit
        self.verificationInstructions = verificationInstructions; self.validation = validation; self.provider = provider
        self.notices = notices; self.cacheKey = cacheKey; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}
