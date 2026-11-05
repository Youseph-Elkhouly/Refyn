import Foundation

/// The structured result the model must return. Validated before use; see `ModelPlan.validated`.
public struct ModelPlan: Codable, Hashable, Sendable {
    public struct Task: Codable, Hashable, Sendable { public var id: String; public var title: String; public var detail: String; public var dependsOn: [String] }
    public struct Reference: Codable, Hashable, Sendable { public var path: String; public var symbol: String?; public var reason: String }
    public struct Planned: Codable, Hashable, Sendable { public var name: String; public var type: String; public var connectsTo: [String] }

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
        var ids = Set<String>()
        for t in tasks { guard ids.insert(t.id).inserted else { throw ValidationError.duplicateTaskID(t.id) } }
        for t in tasks { for d in t.dependsOn where !ids.contains(d) { throw ValidationError.unknownDependency(d) } }
        guard PromptComposer.topologicalOrder(tasks.map { PlanTask(id: $0.id, title: $0.title, dependsOn: $0.dependsOn) }) != nil else { throw ValidationError.cyclicDependencies }
        var copy = self
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
    public init(analysis: RequestAnalysis, mode: PromptMode, techniques: [PromptTechnique], context: RetrievedContext, iterationLimit: Int) {
        self.analysis = analysis; self.mode = mode; self.techniques = techniques; self.context = context; self.iterationLimit = iterationLimit
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
