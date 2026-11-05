import Foundation

public enum PromptMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto = "Auto"
    case basic = "Basic"
    case advanced = "Advanced"
    case custom = "Custom"
    public var id: String { rawValue }
}

public enum PromptTechnique: String, Codable, CaseIterable, Identifiable, Sendable {
    case zeroShot = "Zero-shot"
    case roleContext = "Role and context"
    case structured = "Structured output"
    case fewShot = "Few-shot examples"
    case decomposition = "Task decomposition"
    case concisePlanning = "Observable task steps"
    case selfCritique = "Self-critique"
    case boundedIteration = "Bounded iteration"
    case conditionalBranching = "Conditional branching"
    case reactWorkflow = "Tool-use workflow"
    case verification = "Verification-driven"
    case multiStage = "Multi-stage workflow"
    public var id: String { rawValue }
}

public struct PromptTechniqueRegistry: Sendable {
    public let techniques = PromptTechnique.allCases
    public init() {}

    public func selected(for mode: PromptMode, input: String, custom: Set<PromptTechnique> = []) -> [PromptTechnique] {
        let words = input.split(whereSeparator: \.isWhitespace).count
        switch mode {
        case .basic: return [.zeroShot, .structured]
        case .custom: return PromptTechnique.allCases.filter { custom.contains($0) }
        case .auto:
            guard words > 18 || input.contains("\n") else { return [.zeroShot] }
            return [.roleContext, .structured, .decomposition, .verification]
        case .advanced:
            var result: [PromptTechnique] = [.roleContext, .structured, .decomposition, .concisePlanning, .verification]
            result.append(.boundedIteration)
            if words > 50 { result.append(.selfCritique) }
            if input.localizedCaseInsensitiveContains("if ") || input.localizedCaseInsensitiveContains("unless") { result.append(.conditionalBranching) }
            return result
        }
    }
}

public struct PromptPlan: Codable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var originalPrompt: String
    public var optimizedPrompt: String
    public var selectedWorkspace: URL?
    public var extractedIntent: String
    public var selectedTechniques: [PromptTechnique]
    public var codebaseReferences: [String]
    public var taskSteps: [String]
    public var dependencies: [String]
    public var userConfirmedConstraints: [String]
    public var suggestedDecisions: [String]
    public var successCriteria: [String]
    public var missingInformation: [String]
    public var iterationLimit: Int
    public var verificationInstructions: [String]

    public init(id: UUID = UUID(), createdAt: Date = .now, originalPrompt: String, optimizedPrompt: String = "", selectedWorkspace: URL? = nil, extractedIntent: String = "", selectedTechniques: [PromptTechnique] = [], codebaseReferences: [String] = [], taskSteps: [String] = [], dependencies: [String] = [], userConfirmedConstraints: [String] = [], suggestedDecisions: [String] = [], successCriteria: [String] = [], missingInformation: [String] = [], iterationLimit: Int = 0, verificationInstructions: [String] = []) {
        self.id = id; self.createdAt = createdAt; self.originalPrompt = originalPrompt; self.optimizedPrompt = optimizedPrompt
        self.selectedWorkspace = selectedWorkspace; self.extractedIntent = extractedIntent; self.selectedTechniques = selectedTechniques
        self.codebaseReferences = codebaseReferences; self.taskSteps = taskSteps; self.dependencies = dependencies
        self.userConfirmedConstraints = userConfirmedConstraints; self.suggestedDecisions = suggestedDecisions
        self.successCriteria = successCriteria; self.missingInformation = missingInformation
        self.iterationLimit = iterationLimit; self.verificationInstructions = verificationInstructions
    }
}

public protocol PromptOptimizing: Sendable {
    func optimize(_ input: String, mode: PromptMode, customTechniques: Set<PromptTechnique>, workspace: URL?) async throws -> PromptPlan
}

public struct PromptEngineeringService: PromptOptimizing {
    private let registry = PromptTechniqueRegistry()
    public init() {}

    public func optimize(_ input: String, mode: PromptMode, customTechniques: Set<PromptTechnique> = [], workspace: URL? = nil) async throws -> PromptPlan {
        let original = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { throw PromptError.emptyInput }
        let techniques = registry.selected(for: mode, input: original, custom: customTechniques)
        let steps = techniques.contains(.decomposition) ? ["Inspect the relevant code and identify affected components.", "Implement the requested change while preserving stated constraints.", "Verify the result and report any unresolved issues."] : []
        var result = original
        if techniques.contains(.structured) {
            result += "\n\nRequirements:\n- Preserve all constraints stated above.\n- Keep the change focused on the requested task."
        }
        if !steps.isEmpty {
            result += "\n\nTask steps:\n" + steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        }
        if techniques.contains(.verification) || techniques.contains(.boundedIteration) {
            result += "\n\nVerification:\n- Run the relevant checks and inspect their results.\n- If a check fails, fix the cause and rerun it, up to 3 attempts.\n- Report checks run and any remaining failures."
        }
        return PromptPlan(originalPrompt: original, optimizedPrompt: result, selectedWorkspace: workspace,
                          extractedIntent: original, selectedTechniques: techniques, taskSteps: steps,
                          successCriteria: ["The requested change is implemented.", "Relevant verification results are reported."],
                          iterationLimit: techniques.contains(.boundedIteration) ? 3 : 0,
                          verificationInstructions: techniques.contains(.verification) ? ["Run relevant checks", "Report unresolved failures"] : [])
    }
}

public enum PromptError: Error { case emptyInput }

public actor PromptPlanService {
    private var plans: [PromptPlan] = []
    private let fileURL: URL
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Refine/prompt-plans.json")
        if let data = try? Data(contentsOf: self.fileURL), let decoded = try? JSONDecoder().decode([PromptPlan].self, from: data) { plans = decoded }
    }
    public func allPlans() -> [PromptPlan] { plans }
    public func save(_ plan: PromptPlan) throws {
        plans.insert(plan, at: 0)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(plans).write(to: fileURL, options: .atomic)
    }
}
