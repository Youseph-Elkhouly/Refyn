import Foundation

/// The structured result the model must return. Validated before use; see `ModelPlan.validated`.
public struct ModelPlan: Codable, Hashable, Sendable {
    public struct Task: Codable, Hashable, Sendable {
        public var id: String
        public var title: String
        public var detail: String
        public var dependsOn: [String]

        public init(id: String, title: String, detail: String = "", dependsOn: [String] = []) {
            self.id = id; self.title = title; self.detail = detail; self.dependsOn = dependsOn
        }

        private enum CodingKeys: String, CodingKey { case id, title, detail, dependsOn }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
            dependsOn = try c.decodeIfPresent([String].self, forKey: .dependsOn) ?? []
        }
    }
    public struct Reference: Codable, Hashable, Sendable {
        public var path: String
        public var symbol: String?
        public var reason: String

        public init(path: String, symbol: String? = nil, reason: String) {
            self.path = path; self.symbol = symbol; self.reason = reason
        }

        private enum CodingKeys: String, CodingKey { case path, symbol, reason }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
            symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
            reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        }
    }
    public struct Planned: Codable, Hashable, Sendable {
        public var name: String
        public var type: String
        public var connectsTo: [String]

        public init(name: String, type: String = "library", connectsTo: [String] = []) {
            self.name = name; self.type = type; self.connectsTo = connectsTo
        }

        private enum CodingKeys: String, CodingKey { case name, type, connectsTo }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            type = try c.decodeIfPresent(String.self, forKey: .type) ?? "library"
            connectsTo = try c.decodeIfPresent([String].self, forKey: .connectsTo) ?? []
        }
    }

    public var intent: String
    public var taskType: String
    public var role: String
    public var objective: String
    public var confirmedRequirements: [String]
    public var suggestedDecisions: [String]
    public var constraints: [String]
    public var tasks: [Task]
    public var successCriteria: [String]
    public var missingInformation: [String]
    public var verificationSteps: [String]
    public var codeReferences: [Reference]
    public var plannedComponents: [Planned]?
    public var exampleReport: String?
    public var intentPreserved: Bool
    /// Brackets the output parser had to insert or drop to make the JSON valid. Not part of the model schema.
    public var recoveryEdits = 0

    public init(intent: String, taskType: String, role: String, objective: String, confirmedRequirements: [String] = [],
                suggestedDecisions: [String] = [], constraints: [String] = [], tasks: [Task] = [], successCriteria: [String] = [],
                missingInformation: [String] = [], verificationSteps: [String] = [], codeReferences: [Reference] = [],
                plannedComponents: [Planned]? = nil, exampleReport: String? = nil, intentPreserved: Bool = true) {
        self.intent = intent; self.taskType = taskType; self.role = role; self.objective = objective
        self.confirmedRequirements = confirmedRequirements; self.suggestedDecisions = suggestedDecisions; self.constraints = constraints
        self.tasks = tasks; self.successCriteria = successCriteria; self.missingInformation = missingInformation
        self.verificationSteps = verificationSteps; self.codeReferences = codeReferences; self.plannedComponents = plannedComponents
        self.exampleReport = exampleReport; self.intentPreserved = intentPreserved
    }

    private enum CodingKeys: String, CodingKey {
        case intent, taskType, role, objective, confirmedRequirements, suggestedDecisions, constraints, tasks
        case successCriteria, missingInformation, verificationSteps, codeReferences, plannedComponents, exampleReport, intentPreserved
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intent = try c.decodeIfPresent(String.self, forKey: .intent) ?? ""
        taskType = try c.decodeIfPresent(String.self, forKey: .taskType) ?? ""
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        objective = try c.decodeIfPresent(String.self, forKey: .objective) ?? ""
        confirmedRequirements = Self.strings(c, .confirmedRequirements)
        suggestedDecisions = Self.strings(c, .suggestedDecisions)
        constraints = Self.strings(c, .constraints)
        tasks = try c.decodeIfPresent([Task].self, forKey: .tasks) ?? []
        successCriteria = Self.strings(c, .successCriteria)
        missingInformation = Self.strings(c, .missingInformation)
        verificationSteps = Self.strings(c, .verificationSteps)
        codeReferences = try c.decodeIfPresent([Reference].self, forKey: .codeReferences) ?? []
        plannedComponents = try c.decodeIfPresent([Planned].self, forKey: .plannedComponents)
        exampleReport = try c.decodeIfPresent(String.self, forKey: .exampleReport)
        intentPreserved = try c.decodeIfPresent(Bool.self, forKey: .intentPreserved) ?? true
        // The compact schemas leave these out: the objective doubles as the intent, and the analyzer already knows the task type.
        if intent.trimmingCharacters(in: .whitespaces).isEmpty { intent = objective }
    }

    /// Small models sometimes write a one-item list as a bare string. Accept both rather than discarding the whole plan.
    private static func strings(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String] {
        if let list = try? c.decodeIfPresent([String].self, forKey: key) { return list }
        if let single = try? c.decodeIfPresent(String.self, forKey: key) {
            let trimmed = single.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
        return []
    }

    /// Small models often leave task ids empty or repeat them, and sometimes name a dependency by its title.
    /// Give every task a unique id, resolve title references, and drop dependencies that point nowhere.
    static func repairedTasks(_ tasks: [Task]) -> [Task] {
        var used = Set<String>()
        var fixed = tasks
        for i in fixed.indices {
            var id = fixed[i].id.trimmingCharacters(in: .whitespaces)
            if id.isEmpty || used.contains(id) {
                var n = i + 1
                while used.contains("t\(n)") { n += 1 }
                id = "t\(n)"
            }
            used.insert(id)
            fixed[i].id = id
        }
        let byTitle = Dictionary(fixed.map { ($0.title.lowercased(), $0.id) }, uniquingKeysWith: { first, _ in first })
        for i in fixed.indices {
            fixed[i].dependsOn = fixed[i].dependsOn.compactMap { ref in
                if used.contains(ref) { return ref == fixed[i].id ? nil : ref }
                if let id = byTitle[ref.lowercased()], id != fixed[i].id { return id }
                return nil
            }
        }
        return fixed
    }

    public enum ValidationError: Error, LocalizedError, Equatable {
        case empty(String), duplicateTaskID(String), unknownDependency(String), cyclicDependencies, tooLarge(String)
        public var errorDescription: String? {
            switch self {
            case .empty(let f): "The model returned an empty \(f)."
            case .duplicateTaskID(let id): "The model returned duplicate task id \(id)."
            case .unknownDependency(let id): "A task depends on unknown task \(id)."
            case .cyclicDependencies: "The model returned cyclic task dependencies."
            case .tooLarge(let f): "The model returned too many \(f)."
            }
        }
    }

    /// Schema checks a JSON decoder cannot express. Returns the plan with unverifiable code references removed.
    public func validated(knownPaths: Set<String>) throws -> (ModelPlan, droppedReferences: [String]) {
        guard !intent.trimmingCharacters(in: .whitespaces).isEmpty else { throw ValidationError.empty("intent") }
        guard !objective.trimmingCharacters(in: .whitespaces).isEmpty else { throw ValidationError.empty("objective") }
        for (name, list) in [("tasks", tasks.count), ("constraints", constraints.count), ("success criteria", successCriteria.count), ("references", codeReferences.count)] where list > 25 {
            throw ValidationError.tooLarge(name)
        }
        var copy = self
        copy.tasks = Self.repairedTasks(tasks)
        // Cycles are never repaired silently: they mean the plan is not a usable order.
        guard PromptComposer.topologicalOrder(copy.tasks.map { PlanTask(id: $0.id, title: $0.title, dependsOn: $0.dependsOn) }) != nil else { throw ValidationError.cyclicDependencies }
        // A path the analyzer never saw is not cited as fact.
        let dropped = codeReferences.filter { ref in !knownPaths.contains(ref.path) && !knownPaths.contains(where: { $0.hasPrefix(ref.path + "/") }) }.map(\.path)
        copy.codeReferences.removeAll { dropped.contains($0.path) }
        return (copy, dropped)
    }


}

public struct OptimizationRequest: Sendable, Hashable {
    public var analysis: RequestAnalysis
    public var mode: PromptMode
    public var techniques: [PromptTechnique]
    public var context: RetrievedContext
    public var iterationLimit: Int
    public var userAnswers: [PromptAnswer]
    public var unansweredQuestions: [String]
    public var previousOptimizedPrompt: String?
    public var previousConfirmedRequirements: [String]
    public var correctiveInstruction: String?
    /// Selects the prompt size and output budget. Defaults to the full path.
    public var tier: OptimizationTier
    public init(analysis: RequestAnalysis, mode: PromptMode, techniques: [PromptTechnique], context: RetrievedContext, iterationLimit: Int,
                userAnswers: [PromptAnswer] = [], unansweredQuestions: [String] = [], previousOptimizedPrompt: String? = nil,
                previousConfirmedRequirements: [String] = [], correctiveInstruction: String? = nil, tier: OptimizationTier = .complex) {
        self.tier = tier
        self.analysis = analysis; self.mode = mode; self.techniques = techniques; self.context = context; self.iterationLimit = iterationLimit; self.userAnswers = userAnswers
        self.unansweredQuestions = unansweredQuestions
        self.previousOptimizedPrompt = previousOptimizedPrompt
        self.previousConfirmedRequirements = previousConfirmedRequirements
        self.correctiveInstruction = correctiveInstruction
    }
}

public enum LLMError: Error, LocalizedError, Equatable {
    case modelNotInstalled
    case cancelled
    case unavailable(String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled: "Download the local Qwen model in Settings before optimizing."
        case .cancelled: "Optimization was cancelled."
        case .unavailable(let message): "The local model could not run: \(message)"
        case .invalidResponse(let message): "The local model returned an invalid prompt plan: \(message)"
        }
    }
}

public protocol LLMProvider: Sendable {
    var identifier: String { get }
    func plan(for request: OptimizationRequest) async throws -> ModelPlan
}
