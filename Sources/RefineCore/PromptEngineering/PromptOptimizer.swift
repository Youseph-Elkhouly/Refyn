import CryptoKit
import Foundation

public enum PromptError: Error, LocalizedError, Equatable {
    case emptyInput
    public var errorDescription: String? { "Enter a prompt before optimizing." }
}

/// The optimization pipeline:
/// 1 intent extraction · 2 task classification · 3 context retrieval · 4 technique selection (local, deterministic)
/// 5 decomposition · 6 constraints · 7 success criteria (one structured model call, or local rules offline)
/// 8 prompt construction · 9 intent-preservation validation · 10 final prompt (local, deterministic).
public struct PromptOptimizer: Sendable {
    public struct Input: Sendable {
        public var text: String
        public var mode: PromptMode
        public var customTechniques: Set<PromptTechnique>
        public var workspace: Workspace?
        public var graph: CodebaseGraph?
        public var notes: [Note]
        public var iterationLimit: Int
        public init(text: String, mode: PromptMode, customTechniques: Set<PromptTechnique> = [], workspace: Workspace? = nil, graph: CodebaseGraph? = nil,
                    notes: [Note] = [], iterationLimit: Int = 3) {
            self.text = text; self.mode = mode; self.customTechniques = customTechniques; self.workspace = workspace; self.graph = graph
            self.notes = notes; self.iterationLimit = iterationLimit
        }
    }

    let provider: (any LLMProvider)?
    let registry = TechniqueRegistry()

    /// With no provider, plans are built by local rules only.
    public init(provider: (any LLMProvider)?) { self.provider = provider }

    public func cacheKey(for input: Input) -> String {
        let analysis = RequestAnalysis(input.text)
        let context = ContextRetriever.retrieve(for: analysis, workspaceName: input.workspace?.name ?? "", graph: input.graph, notes: input.notes)
        let parts = [analysis.text, input.mode.rawValue, input.customTechniques.map(\.rawValue).sorted().joined(separator: ","), context.hash,
                     String(input.iterationLimit), provider?.identifier ?? "local", "v1"]
        return SHA256.hash(data: Data(parts.joined(separator: "\u{1F}").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func optimize(_ input: Input) async throws -> PromptPlan {
        // 1–2: intent and task type.
        let analysis = RequestAnalysis(input.text)
        guard !analysis.text.isEmpty else { throw PromptError.emptyInput }
        // 3: context, bounded and never whole files.
        let context = ContextRetriever.retrieve(for: analysis, workspaceName: input.workspace?.name ?? "", graph: input.graph, notes: input.notes)
        // 4: techniques.
        let techniques = registry.select(mode: input.mode, analysis: analysis, custom: input.customTechniques, hasContext: !context.isEmpty)
        let iterationLimit = techniques.contains(.boundedIteration) ? max(1, min(10, input.iterationLimit)) : 0

        // 5–7: model call when available, local rules otherwise.
        var notices: [String] = []
        var modelPlan: ModelPlan?
        var providerID = "local"
        if let provider {
            do {
                let raw = try await provider.plan(for: OptimizationRequest(analysis: analysis, mode: input.mode, techniques: techniques, context: context, iterationLimit: iterationLimit))
                let (valid, dropped) = try raw.validated(knownPaths: context.knownPaths)
                modelPlan = valid
                providerID = provider.identifier
                if !dropped.isEmpty { notices.append("Removed \(dropped.count) file reference(s) the analyzer could not confirm: \(dropped.prefix(3).joined(separator: ", "))") }
            } catch let error as LLMError where error != .invalidAPIKey {
                notices.append("\(error.localizedDescription) Built locally instead.")
            } catch let error as ModelPlan.ValidationError {
                notices.append("\(error.localizedDescription) Built locally instead.")
            }
        } else {
            notices.append("Built locally (no model configured).")
        }

        var plan = modelPlan.map { Self.plan(from: $0, analysis: analysis, context: context) } ?? Self.localPlan(analysis: analysis, context: context)
        plan.workspaceID = input.workspace?.id
        plan.mode = input.mode
        plan.selectedTechniques = techniques
        plan.iterationLimit = iterationLimit
        plan.provider = providerID
        plan.cacheKey = cacheKey(for: input)

        // 8: construction.
        let parts = PromptComposer.Parts(role: modelPlan?.role.nilIfEmpty ?? Self.defaultRole(context), objective: modelPlan?.objective ?? analysis.intent,
                                         exampleReport: modelPlan?.exampleReport, context: context)
        var prompt = PromptComposer.compose(plan, parts: parts)
        plan.chainedPrompts = PromptComposer.chain(plan, parts: parts)

        // 9: intent preservation. Anything specific the user wrote must survive; if not, quote the original.
        let missing = analysis.missingTerms(in: prompt + "\n" + plan.chainedPrompts.joined(separator: "\n"))
        plan.validation = IntentValidation(missingTerms: missing, modelReportedPreserved: modelPlan?.intentPreserved, repaired: false)
        if !missing.isEmpty || modelPlan?.intentPreserved == false {
            prompt += "\n\n## Original request (verbatim)\n> " + analysis.text.replacingOccurrences(of: "\n", with: "\n> ")
            plan.validation.repaired = true
            if !plan.chainedPrompts.isEmpty { plan.chainedPrompts[0] += "\n\n## Original request (verbatim)\n> " + analysis.text.replacingOccurrences(of: "\n", with: "\n> ") }
        }

        // 10: final.
        plan.optimizedPrompt = prompt
        plan.notices = notices
        plan.updatedAt = .now
        return plan
    }

    static func defaultRole(_ ctx: RetrievedContext) -> String {
        let stack = ctx.frameworks.isEmpty ? (ctx.languages.isEmpty ? "" : " (\(ctx.languages.joined(separator: ", ")))") : " (\(ctx.frameworks.prefix(4).joined(separator: ", ")))"
        return "You are a senior engineer working in the \(ctx.workspaceName.isEmpty ? "current" : "`\(ctx.workspaceName)`") repository\(stack). Make focused, production-quality changes that follow the existing patterns."
    }

    static func plan(from m: ModelPlan, analysis: RequestAnalysis, context: RetrievedContext) -> PromptPlan {
        let componentIDs = Set(context.components.map(\.id))
        return PromptPlan(
            originalPrompt: analysis.text,
            intent: m.intent,
            taskType: TaskType(rawValue: m.taskType) ?? analysis.taskType,
            codeReferences: m.codeReferences.map { CodeReference(path: $0.path, symbol: $0.symbol?.nilIfEmpty, reason: $0.reason, source: .model) },
            tasks: m.tasks.map { PlanTask(id: $0.id, title: $0.title, detail: $0.detail, dependsOn: $0.dependsOn) },
            constraints: dedupe(analysis.constraints + m.constraints),
            successCriteria: m.successCriteria,
            missingInformation: m.missingInformation,
            confirmedRequirements: m.confirmedRequirements,
            suggestedDecisions: m.suggestedDecisions,
            plannedComponents: (m.plannedComponents ?? []).enumerated().map { i, p in
                PlannedComponent(id: "p\(i + 1)", name: p.name, type: ComponentType(rawValue: p.type) ?? .library, connectsTo: p.connectsTo.filter(componentIDs.contains))
            },
            verificationInstructions: m.verificationSteps)
    }

    /// The offline plan: everything here comes from the request text and the analyzer, nothing invented.
    static func localPlan(analysis: RequestAnalysis, context: RetrievedContext) -> PromptPlan {
        let refs = context.components.prefix(5).map { CodeReference(path: $0.path, symbol: nil, reason: "\($0.type) module matching the request", source: .graph) }
        let tasks: [PlanTask]
        switch analysis.taskType {
        case .bugfix:
            tasks = [PlanTask(id: "t1", title: "Reproduce the problem", detail: "Find or write the smallest failing case."),
                     PlanTask(id: "t2", title: "Locate the cause", detail: "Trace the failing path in the code.", dependsOn: ["t1"]),
                     PlanTask(id: "t3", title: "Fix the cause", detail: "Make the smallest change that fixes it.", dependsOn: ["t2"]),
                     PlanTask(id: "t4", title: "Add a regression test", dependsOn: ["t3"])]
        case .refactor:
            tasks = [PlanTask(id: "t1", title: "Map current usages", detail: "Find every caller of the code being changed."),
                     PlanTask(id: "t2", title: "Restructure", detail: "Change the code without changing behavior.", dependsOn: ["t1"]),
                     PlanTask(id: "t3", title: "Update callers", dependsOn: ["t2"])]
        case .investigation:
            tasks = [PlanTask(id: "t1", title: "Trace the relevant code paths"), PlanTask(id: "t2", title: "Summarize findings with file references", dependsOn: ["t1"])]
        default:
            tasks = [PlanTask(id: "t1", title: "Inspect the affected code", detail: "Identify where the change belongs."),
                     PlanTask(id: "t2", title: "Implement the change", detail: "Follow existing patterns.", dependsOn: ["t1"]),
                     PlanTask(id: "t3", title: "Cover it with tests", dependsOn: ["t2"])]
        }
        let criteria: [String] = switch analysis.taskType {
        case .bugfix: ["The reported problem no longer occurs.", "A test fails before the fix and passes after it.", "Existing tests still pass."]
        case .refactor: ["Behavior is unchanged; existing tests pass without modification.", "No caller is left on the old structure."]
        case .investigation: ["Every claim cites a file and line."]
        default: ["The requested behavior works as described.", "Existing tests and the build pass."]
        }
        return PromptPlan(originalPrompt: analysis.text, intent: analysis.intent, taskType: analysis.taskType, codeReferences: refs, tasks: tasks,
                          constraints: analysis.constraints, successCriteria: criteria, confirmedRequirements: [analysis.intent],
                          verificationInstructions: ["Run the existing tests for the affected code.", "Run the build or type checker."])
    }

    static func dedupe(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))).inserted }
    }
}
