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
        public var userAnswers: [PromptAnswer]
        public var unansweredQuestions: [String]
        public init(text: String, mode: PromptMode, customTechniques: Set<PromptTechnique> = [], workspace: Workspace? = nil, graph: CodebaseGraph? = nil,
                    notes: [Note] = [], iterationLimit: Int = 3, userAnswers: [PromptAnswer] = [], unansweredQuestions: [String] = []) {
            self.text = text; self.mode = mode; self.customTechniques = customTechniques; self.workspace = workspace; self.graph = graph
            self.notes = notes; self.iterationLimit = iterationLimit; self.userAnswers = userAnswers; self.unansweredQuestions = unansweredQuestions
        }
    }

    let provider: (any LLMProvider)?
    let registry = TechniqueRegistry()

    /// With no provider, plans are built by local rules only.
    public init(provider: (any LLMProvider)?) { self.provider = provider }

    public func cacheKey(for input: Input) -> String {
        let analysis = RequestAnalysis(input.text, confirmedRequirements: input.userAnswers.map(\.answer))
        let context = ContextRetriever.retrieve(for: analysis, workspaceName: input.workspace?.name ?? "", graph: input.graph, notes: input.notes)
        let parts = [analysis.text, input.mode.rawValue, input.customTechniques.map(\.rawValue).sorted().joined(separator: ","), context.hash,
                     input.userAnswers.map { "\($0.id):\($0.answer)" }.joined(separator: "\n"), input.unansweredQuestions.joined(separator: "\n"),
                     String(input.iterationLimit), provider?.identifier ?? "local", "v3"]
        return SHA256.hash(data: Data(parts.joined(separator: "\u{1F}").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func optimize(_ input: Input) async throws -> PromptPlan {
        // 1–2: intent and task type.
        let analysis = RequestAnalysis(input.text, confirmedRequirements: input.userAnswers.map(\.answer))
        guard !analysis.text.isEmpty else { throw PromptError.emptyInput }
        // 3: context, bounded and never whole files.
        let context = ContextRetriever.retrieve(for: analysis, workspaceName: input.workspace?.name ?? "", graph: input.graph, notes: input.notes)
        let answeredGapIDs = Set(input.userAnswers.map(\.id))
        let pendingGaps = analysis.gaps(context: context).filter { !answeredGapIDs.contains($0.id) }
        // Turning the question step off is equivalent to skipping it: preserve the gaps in the
        // prompt and tell the model to keep them open rather than silently guessing.
        let unansweredQuestions = Self.dedupe(input.unansweredQuestions + pendingGaps.map(\.question))
        // 4: techniques.
        var techniques = registry.select(mode: input.mode, analysis: analysis, custom: input.customTechniques, hasContext: !context.isEmpty)
        let iterationLimit = techniques.contains(.boundedIteration) ? max(1, min(10, input.iterationLimit)) : 0

        // 5–7: model call when available, local rules otherwise.
        var notices: [String] = []
        var modelPlan: ModelPlan?
        var providerID = "local"
        // A short prompt can still be an underspecified feature or bug fix. The app's
        // clarification step runs before this pipeline; after answers (or an explicit skip),
        // do not bypass the model and return the original sentence as a "Local rules" result.
        let guidance = Playbook.match(analysis, context: context)
        let needsEngineering = guidance != nil || !pendingGaps.isEmpty || !input.userAnswers.isEmpty || !unansweredQuestions.isEmpty
        // With a model available, even a simple request is worth improving. A bare zero-shot rewrite would hand
        // back the user's own sentence, so use the structured sections instead (the composer drops empty ones).
        let originalTechniques = techniques
        let lightweight = techniques.allSatisfy { [.zeroShot, .contextInjection, .constraints].contains($0) }
        if input.mode != .custom && lightweight && (needsEngineering || provider != nil) {
            techniques = PromptTechnique.allCases.filter { [.structured, .constraints, .acceptanceCriteria].contains($0) || ($0 == .outputFormat && guidance != nil) || ($0 == .contextInjection && !context.isEmpty) }
        }
        let directRewrite = provider == nil || (input.mode == .custom && !needsEngineering && techniques.contains(.zeroShot) && lightweight)
        if let provider {
            if !directRewrite {
                let request = OptimizationRequest(analysis: analysis, mode: input.mode, techniques: techniques, context: context,
                                                 iterationLimit: iterationLimit, userAnswers: input.userAnswers,
                                                 unansweredQuestions: unansweredQuestions)
                do {
                    let raw = try await provider.plan(for: request)
                    let (valid, dropped) = try raw.validated(knownPaths: context.knownPaths)
                    let first = InventionGuard.apply(to: valid, analysis: analysis, context: context, allowedNumbers: iterationLimit > 0 ? [iterationLimit] : [])
                    if first.hasViolations || !dropped.isEmpty {
                        // One bounded correction attempt: local generation is expensive, so never loop.
                        let issues = (first.unverified + first.demoted + dropped).prefix(12).joined(separator: "; ")
                        let correction = "The previous draft introduced unsupported specifics: \(issues). Regenerate the JSON plan using only details found in the user request, user answers, or retrieved workspace context. Remove unsupported details from actionable fields; do not guess."
                        let retryRequest = OptimizationRequest(analysis: analysis, mode: input.mode, techniques: techniques, context: context,
                                                               iterationLimit: iterationLimit, userAnswers: input.userAnswers,
                                                               unansweredQuestions: unansweredQuestions, correctiveInstruction: correction)
                        do {
                            let retryRaw = try await provider.plan(for: retryRequest)
                            let (retryValid, retryDropped) = try retryRaw.validated(knownPaths: context.knownPaths)
                            let retry = InventionGuard.apply(to: retryValid, analysis: analysis, context: context,
                                                            allowedNumbers: iterationLimit > 0 ? [iterationLimit] : [])
                            if retry.hasViolations || !retryDropped.isEmpty {
                                notices += retry.notices
                                if !retryDropped.isEmpty { notices.append("Removed unverified file references: \(retryDropped.prefix(3).joined(separator: ", ")).") }
                                notices.append("The model repeated unsupported details after one correction attempt; used the deterministic prompt builder.")
                            } else {
                                modelPlan = retry.plan
                                providerID = provider.identifier
                            }
                        } catch let error as LLMError where error == .cancelled {
                            throw error
                        } catch {
                            notices.append("The corrective generation did not complete; used the deterministic prompt builder. \(error.localizedDescription)")
                        }
                    } else {
                        modelPlan = first.plan
                        providerID = provider.identifier
                    }
                } catch let error as ModelPlan.ValidationError {
                    notices.append("The local model returned an invalid plan (\(error.localizedDescription)); used the deterministic local prompt builder instead.")
                } catch let error as LLMError {
                    if case .invalidResponse = error {
                        notices.append("The local model returned malformed output; used the deterministic local prompt builder instead.")
                    } else if error == .modelNotInstalled, !needsEngineering {
                        // A simple request still works without the model; only the extra improvement is skipped.
                        techniques = originalTechniques
                        notices.append("The local model is not installed, so this simple request was only cleaned up. Download it in Settings for a fuller rewrite.")
                    } else {
                        throw error
                    }
                }
            }
        } else {
            notices.append("Built locally (no model configured).")
        }

        var plan = modelPlan.map { Self.plan(from: $0, analysis: analysis, context: context, unanswered: unansweredQuestions) } ?? Self.localPlan(analysis: analysis, context: context)
        plan.workspaceID = input.workspace?.id
        plan.mode = input.mode
        plan.selectedTechniques = techniques
        plan.iterationLimit = iterationLimit
        plan.provider = providerID
        plan.guidance = guidance
        plan.cacheKey = cacheKey(for: input)
        plan.missingInformation = Self.dedupe(plan.missingInformation + unansweredQuestions)

        // 8: construction.
        let modelRole = modelPlan?.role.trimmingCharacters(in: .whitespacesAndNewlines)
        let role = modelRole.flatMap { $0.count >= 16 && $0.lowercased() != "refine" ? $0 : nil } ?? Self.defaultRole(context)
        var objective = modelPlan?.objective ?? analysis.intent
        if guidance != nil, modelPlan == nil {
            if let preface = objective.range(of: #"^.*?\bprompt\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) {
                objective = String(objective[preface.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                objective = objective.prefix(1).uppercased() + objective.dropFirst()
            }
            objective += objective.hasSuffix(".") ? "" : "."
            if let direction = guidance?.direction {
                objective += " The user wants it to feel \(direction); the target quality below is derived from that."
            } else {
                objective += " The request does not say what exactly is wrong, so first establish that, then fix it."
            }
        }
        let parts = PromptComposer.Parts(role: role, objective: objective,
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

    static func plan(from m: ModelPlan, analysis: RequestAnalysis, context: RetrievedContext, unanswered: [String] = []) -> PromptPlan {
        let componentIDs = Set(context.components.map(\.id))
        // Restating the whole request as a "requirement" adds nothing: the objective already says it.
        var m = m
        m.confirmedRequirements.removeAll { semanticallySimilar($0, analysis.text) && groundedWordCoverage(analysis.text, $0) >= 0.8 }
        m.constraints.removeAll { $0.count > 40 && groundedWordCoverage(analysis.text, $0) >= 0.8 && groundedWordCoverage($0, analysis.text) >= 0.8 }
        let confirmed = m.confirmedRequirements
        let taskText = m.tasks.map { "\($0.title) \($0.detail)" }
        let userConfirmed = dedupe(analysis.confirmedRequirements)
        let explicitlyReferencesNotes = analysis.text.range(of: #"\bnotes?\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        let userStatements = analysis.constraints + userConfirmed + [analysis.text] + (explicitlyReferencesNotes ? context.notes : [])
        func grounded(_ candidate: String) -> Bool {
            userStatements.contains { source in
                source.localizedCaseInsensitiveContains(candidate) || semanticallySimilar(candidate, source)
                    || groundedWordCoverage(candidate, source) >= 0.55
            }
        }
        let groundedModelConstraints = m.constraints.filter { candidate in
            grounded(candidate)
        }
        let optionalModelConstraints = m.constraints.filter { !groundedModelConstraints.contains($0) }
        let additionalConfirmed = m.confirmedRequirements.filter { candidate in
            grounded(candidate) && !userConfirmed.contains { supplied in
                supplied.localizedCaseInsensitiveContains(candidate) || semanticallySimilar(candidate, supplied)
            }
        }
        let optionalModelRequirements = m.confirmedRequirements.filter { !grounded($0) }
        // A proposed outcome stays an acceptance criterion when the request supports it, or when it adds no new
        // codebase fact and does not answer a question the user skipped. Anything else is only a suggestion.
        let requestText = analysis.searchText.lowercased()
        func isProposable(_ criterion: String) -> Bool {
            if grounded(criterion) { return true }
            let newFacts = RequestAnalysis.keyTerms(criterion).filter { !InventionGuard.isValue($0) && !requestText.contains($0.lowercased()) }
            if !newFacts.isEmpty { return false }
            return !unanswered.contains { groundedWordCoverage($0, criterion) >= 0.35 }
        }
        let groundedCriteria = m.successCriteria.filter(isProposable)
        let optionalModelCriteria = m.successCriteria.filter { !isProposable($0) }
        return PromptPlan(
            originalPrompt: analysis.text,
            intent: m.intent,
            taskType: TaskType(rawValue: m.taskType) ?? analysis.taskType,
            codeReferences: m.codeReferences.map { CodeReference(path: $0.path, symbol: $0.symbol?.nilIfEmpty, reason: $0.reason, source: .model) },
            tasks: m.tasks.map { PlanTask(id: $0.id, title: $0.title, detail: $0.detail, dependsOn: $0.dependsOn) },
            constraints: nonRedundant(dedupe(analysis.constraints + groundedModelConstraints), against: confirmed),
            successCriteria: groundedCriteria,
            missingInformation: m.missingInformation,
            confirmedRequirements: dedupe(userConfirmed + additionalConfirmed),
            suggestedDecisions: nonRedundant(m.suggestedDecisions + optionalModelConstraints + optionalModelRequirements + optionalModelCriteria,
                                             against: confirmed + taskText + analysis.constraints),
            plannedComponents: (m.plannedComponents ?? []).enumerated().map { i, p in
                PlannedComponent(id: "p\(i + 1)", name: p.name, type: ComponentType(rawValue: p.type) ?? .library, connectsTo: p.connectsTo.filter(componentIDs.contains))
            },
            verificationInstructions: verificationSteps(modelSteps: m.verificationSteps, request: analysis.text))
    }

    /// Keep named test scenarios, but don't let the model invent what each scenario should do.
    static func verificationSteps(modelSteps: [String], request: String) -> [String] {
        let nsRequest = request as NSString
        guard let regex = try? NSRegularExpression(pattern: #"\btests?\s+([^.!?\n]+)"#, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: request, range: NSRange(location: 0, length: nsRequest.length)),
              let range = Range(match.range(at: 1), in: request) else { return modelSteps }
        var scenarios = String(request[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" cases", " case"] where scenarios.lowercased().hasSuffix(suffix) {
            scenarios = String(scenarios.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        guard !scenarios.isEmpty, scenarios.count <= 160,
              ![" then ", " fix ", " stop ", " and report "].contains(where: { scenarios.localizedCaseInsensitiveContains($0) }) else {
            return modelSteps
        }
        return ["Test the requested cases (\(scenarios)). Verify outcomes stated in the request; where an outcome is unspecified, observe and preserve existing behavior."]
    }

    /// The offline plan: everything here comes from the request text and the analyzer, nothing invented.
    static func localPlan(analysis: RequestAnalysis, context: RetrievedContext) -> PromptPlan {
        if analysis.complexity < 2 {
            return PromptPlan(originalPrompt: analysis.text, intent: analysis.intent, taskType: analysis.taskType,
                              constraints: analysis.constraints, confirmedRequirements: dedupe(analysis.confirmedRequirements))
        }
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
                          constraints: analysis.constraints, successCriteria: criteria, confirmedRequirements: dedupe(analysis.confirmedRequirements),
                          verificationInstructions: ["Run the existing tests for the affected code.", "Run the build or type checker."])
    }

    static func dedupe(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))).inserted }
    }

    static func nonRedundant(_ items: [String], against reference: [String]) -> [String] {
        var kept: [String] = []
        for item in items where !(reference + kept).contains(where: { semanticallySimilar(item, $0) }) { kept.append(item) }
        return kept
    }

    static func semanticallySimilar(_ lhs: String, _ rhs: String) -> Bool {
        let ignored: Set<String> = ["a", "an", "the", "to", "of", "for", "and", "or", "do", "does", "not", "no", "is", "are", "be", "with", "during", "up", "on", "in"]
        func words(_ value: String) -> Set<String> { normalizedWords(value).subtracting(ignored) }
        let a = words(lhs), b = words(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return Double(a.intersection(b).count) / Double(a.union(b).count) >= 0.66
    }

    static func groundedWordCoverage(_ candidate: String, _ source: String) -> Double {
        let ignored: Set<String> = ["a", "an", "the", "to", "of", "for", "and", "or", "do", "does", "not", "no", "is", "are", "be", "with", "during", "up", "on", "in"]
        let requested = normalizedWords(candidate).subtracting(ignored)
        guard !requested.isEmpty else { return 0 }
        return Double(requested.intersection(normalizedWords(source)).count) / Double(requested.count)
    }

    static func normalizedWords(_ value: String) -> Set<String> {
        Set(value.lowercased().split { !$0.isLetter && !$0.isNumber }.map { raw in
            var word = String(raw)
            if ["paginate", "pagination", "paginated", "paginating"].contains(word) { word = "paginate" }
            else if word.hasSuffix("ies"), word.count > 4 { word = String(word.dropLast(3)) + "y" }
            else if word.hasSuffix("s"), word.count > 3 { word.removeLast() }
            return word
        })
    }
}
