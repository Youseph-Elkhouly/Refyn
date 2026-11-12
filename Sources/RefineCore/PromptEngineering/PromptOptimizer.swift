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
        /// A previously generated prompt to revise when the user remembers more context.
        public var previousOptimizedPrompt: String?
        /// Requirements the user already confirmed in the previous optimization.
        public var previousConfirmedRequirements: [String]
        /// The saved result this new plan revises; remains optional for ordinary optimization.
        public var revisionOf: UUID?
        public init(text: String, mode: PromptMode, customTechniques: Set<PromptTechnique> = [], workspace: Workspace? = nil, graph: CodebaseGraph? = nil,
                    notes: [Note] = [], iterationLimit: Int = 3, userAnswers: [PromptAnswer] = [], unansweredQuestions: [String] = [],
                    previousOptimizedPrompt: String? = nil, previousConfirmedRequirements: [String] = [], revisionOf: UUID? = nil) {
            self.text = text; self.mode = mode; self.customTechniques = customTechniques; self.workspace = workspace; self.graph = graph
            self.notes = notes; self.iterationLimit = iterationLimit; self.userAnswers = userAnswers; self.unansweredQuestions = unansweredQuestions
            self.previousOptimizedPrompt = previousOptimizedPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            self.previousConfirmedRequirements = previousConfirmedRequirements
            self.revisionOf = revisionOf
        }
    }

    let provider: (any LLMProvider)?
    let registry = TechniqueRegistry()

    /// With no provider, plans are built by local rules only.
    public init(provider: (any LLMProvider)?) { self.provider = provider }

    public func cacheKey(for input: Input) -> String {
        let analysis = RequestAnalysis(input.text, confirmedRequirements: input.userAnswers.map(\.answer) + input.previousConfirmedRequirements)
        let context = ContextRetriever.retrieve(for: analysis, workspaceName: input.workspace?.name ?? "", graph: input.graph, notes: input.notes)
        let techniqueKey = input.customTechniques.map(\.rawValue).sorted().joined(separator: ",")
        let answerKey = input.userAnswers.map { "\($0.id):\($0.answer)" }.joined(separator: "\n")
        let confirmedKey = input.previousConfirmedRequirements.joined(separator: "\n")
        var parts = [analysis.text, input.mode.rawValue, techniqueKey, context.hash, answerKey, input.unansweredQuestions.joined(separator: "\n")]
        parts.append(input.previousOptimizedPrompt ?? "")
        parts.append(confirmedKey)
        parts.append(input.revisionOf?.uuidString ?? "")
        parts.append(String(input.iterationLimit))
        parts.append(provider?.identifier ?? "local")
        parts.append("v6-context-revision")
        return SHA256.hash(data: Data(parts.joined(separator: "\u{1F}").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func optimize(_ input: Input) async throws -> PromptPlan {
        // 1–2: intent and task type.
        let analysis = RequestAnalysis(input.text, confirmedRequirements: input.userAnswers.map(\.answer) + input.previousConfirmedRequirements)
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
        let hasPreviousDraft = input.previousOptimizedPrompt != nil
        let needsEngineering = guidance != nil || !pendingGaps.isEmpty || !input.userAnswers.isEmpty || !unansweredQuestions.isEmpty || hasPreviousDraft
        // Route by complexity before spending any compute: small requests are improved instantly by local rules,
        // moderate ones get one compact model call, complex ones the full instructions.
        let tier = OptimizationRouter.tier(analysis: analysis, mode: input.mode, pendingGaps: unansweredQuestions.count, hasLocalCoverage: QuickRecipes.recipe(for: analysis) != nil || guidance?.kind == .diagnose,
                                           hasAnswers: !input.userAnswers.isEmpty, hasContext: !context.isEmpty)
        // Revisions must pass through the model so the remembered detail can be integrated into
        // the already optimized draft, even when the addendum alone looks like a simple request.
        let quick = input.previousOptimizedPrompt == nil && input.mode != .custom && tier == .simple
        let originalTechniques = techniques
        let lightweight = techniques.allSatisfy { [.zeroShot, .contextInjection, .constraints].contains($0) }
        if quick {
            techniques = PromptTechnique.allCases.filter { [.structured, .constraints, .decomposition, .acceptanceCriteria, .verification].contains($0)
                || ($0 == .outputFormat && guidance != nil) || ($0 == .contextInjection && !context.isEmpty) }
        } else if input.mode != .custom && lightweight && (needsEngineering || provider != nil) {
            techniques = PromptTechnique.allCases.filter { [.structured, .constraints, .acceptanceCriteria].contains($0) || ($0 == .outputFormat && guidance != nil) || ($0 == .contextInjection && !context.isEmpty) }
        }
        let requestTier: OptimizationTier = input.mode == .custom ? .complex : tier
        let directRewrite = provider == nil || quick || (input.mode == .custom && !needsEngineering && techniques.contains(.zeroShot) && lightweight)
        var trace = PipelineTrace(tier: requestTier.rawValue)
        if let provider {
            if !directRewrite {
                let request = OptimizationRequest(analysis: analysis, mode: input.mode, techniques: techniques, context: context,
                                                 iterationLimit: iterationLimit, userAnswers: input.userAnswers,
                                                 unansweredQuestions: unansweredQuestions,
                                                 previousOptimizedPrompt: input.previousOptimizedPrompt,
                                                 previousConfirmedRequirements: input.previousConfirmedRequirements,
                                                 tier: requestTier)
                let allowed: Set<Int> = iterationLimit > 0 ? [iterationLimit] : []
                struct Attempt {
                    var guarded: InventionGuard.Result
                    var dropped: [String]
                    var corrections: [SemanticValidator.Correction]
                    var semanticObjective: String
                }
                /// One model call followed by the local checks: schema, semantic correction, then invention detection.
                func attempt(_ req: OptimizationRequest) async throws -> Attempt {
                    trace.modelCalls += 1
                    let raw = try await provider.plan(for: req)
                    if raw.recoveryEdits > 0 { trace.jsonRecoveryEdits += raw.recoveryEdits; trace.add("json", "recovered", "\(raw.recoveryEdits) bracket edit(s)") }
                    trace.add("parsed", "counts", "tasks=\(raw.tasks.count), verification=\(raw.verificationSteps.count)")
                    let (valid, dropped) = try raw.validated(knownPaths: context.knownPaths)
                    trace.add("schema", "counts", "tasks=\(valid.tasks.count), verification=\(valid.verificationSteps.count)")
                    // Fix contradictions and narrowing first, locally, so they neither trigger a retry nor a fallback.
                    let (semantic, corrections) = SemanticValidator.correctWithReport(valid, analysis: analysis, context: context)
                    trace.corrections += corrections.count
                    for c in corrections { trace.add("semantic", c.action.rawValue, "\(c.list): \(c.clause) (\(c.reason))") }
                    trace.add("semantic", "counts", "tasks=\(semantic.tasks.count), verification=\(semantic.verificationSteps.count)")
                    let guarded = InventionGuard.apply(to: semantic, analysis: analysis, context: context, allowedNumbers: allowed)
                    trace.add("guarded", "counts", "tasks=\(guarded.plan.tasks.count), verification=\(guarded.plan.verificationSteps.count)")
                    if guarded.hasViolations { trace.add("invention-guard", "repaired", "\((guarded.unverified + guarded.demoted).prefix(4).joined(separator: "; "))") }
                    return Attempt(guarded: guarded, dropped: dropped, corrections: corrections, semanticObjective: semantic.objective)
                }
                func fallback(_ reason: String, _ notice: String) {
                    trace.fallbackReason = reason; trace.add("fallback", "local-builder", reason); notices.append(notice)
                }
                do {
                    var first: Attempt
                    do {
                        first = try await attempt(request)
                    } catch let error as LLMError {
                        guard case .invalidResponse(let message) = error else { throw error }
                        // One retry of the same request for unusable output; it is sampled, so it often succeeds.
                        trace.retries += 1; trace.add("model", "unusable-output", message); trace.add("retry", "same-prompt", "unusable output")
                        first = try await attempt(request)
                    } catch let error as ModelPlan.ValidationError {
                        trace.retries += 1; trace.add("model", "invalid-plan", error.localizedDescription); trace.add("retry", "same-prompt", "invalid plan")
                        first = try await attempt(request)
                    }
                    notices += SemanticValidator.notice(for: first.corrections).map { [$0] } ?? []
                    var chosen = first
                    // Retry only when the repaired plan lost its substance. The guard already moves unsupported detail to suggestions,
                    // so a second 10–20 s generation for a cosmetic issue is not worth the latency.
                    let severe = first.guarded.plan.tasks.isEmpty || (first.guarded.demoted.contains(first.semanticObjective) && requestTier == .complex)
                    if requestTier == .complex, severe, first.guarded.hasViolations, trace.retries == 0 {
                        let issues = (first.guarded.unverified + first.guarded.demoted + first.dropped).prefix(12).joined(separator: "; ")
                        let correction = "The previous draft introduced unsupported specifics: \(issues). Regenerate the JSON plan using only details found in the user request, user answers, or retrieved workspace context. Remove unsupported details from actionable fields; do not guess."
                        trace.retries += 1; trace.add("retry", "corrective", "plan lost its substance: \(issues.prefix(160))")
                        let retryRequest = OptimizationRequest(analysis: analysis, mode: input.mode, techniques: techniques, context: context,
                                                               iterationLimit: iterationLimit, userAnswers: input.userAnswers,
                                                               unansweredQuestions: unansweredQuestions,
                                                               previousOptimizedPrompt: input.previousOptimizedPrompt,
                                                               previousConfirmedRequirements: input.previousConfirmedRequirements,
                                                               correctiveInstruction: correction, tier: requestTier)
                        do {
                            let second = try await attempt(retryRequest)
                            if !second.guarded.plan.tasks.isEmpty { chosen = second }
                        } catch let error as LLMError where error == .cancelled {
                            throw error
                        } catch {
                            trace.add("retry", "failed", error.localizedDescription)
                        }
                    }
                    let p = chosen.guarded.plan
                    if p.tasks.isEmpty, p.suggestedDecisions.isEmpty, p.confirmedRequirements.isEmpty, p.constraints.isEmpty, p.successCriteria.isEmpty, p.verificationSteps.isEmpty {
                        fallback("model plan had no usable content after checks", "The local model's plan had no usable content after checks; used the deterministic prompt builder.")
                    } else {
                        modelPlan = chosen.guarded.plan
                        providerID = provider.identifier
                        notices += chosen.guarded.notices
                        if !chosen.dropped.isEmpty { notices.append("Removed unverified file references: \(chosen.dropped.prefix(3).joined(separator: ", ")).") }
                        trace.add("model", "accepted", "tier \(requestTier.rawValue), \(trace.modelCalls) call(s)")
                    }
                } catch let error as ModelPlan.ValidationError {
                    fallback("invalid plan after retry: \(error.localizedDescription)", "The local model returned an invalid plan (\(error.localizedDescription)); used the deterministic local prompt builder instead.")
                } catch let error as LLMError {
                    if case .invalidResponse(let message) = error {
                        fallback("unusable output after retry: \(message.prefix(120))", "The local model returned malformed output twice; used the deterministic local prompt builder instead.")
                    } else if error == .modelNotInstalled, !needsEngineering {
                        // A simple request still works without the model; only the extra improvement is skipped.
                        techniques = originalTechniques
                        trace.add("model", "not-installed", "simple request cleaned up locally")
                        notices.append("The local model is not installed, so this simple request was only cleaned up. Download it in Settings for a fuller rewrite.")
                    } else {
                        throw error
                    }
                }
            }
        } else {
            notices.append("Built locally (no model configured).")
        }

        var plan = modelPlan.map { Self.plan(from: $0, analysis: analysis, context: context, unanswered: unansweredQuestions) } ?? Self.localPlan(analysis: analysis, context: context, quick: quick)
        SemanticValidator.complete(&plan, analysis: analysis, definitions: !quick)
        plan.workspaceID = input.workspace?.id
        plan.revisionOf = input.revisionOf
        plan.mode = input.mode
        plan.selectedTechniques = techniques
        plan.iterationLimit = iterationLimit
        plan.provider = providerID
        plan.guidance = guidance
        plan.cacheKey = cacheKey(for: input)
        plan.missingInformation = Self.dedupe(plan.missingInformation + unansweredQuestions)
        if input.mode != .custom || techniques.contains(.decomposition) || techniques.contains(.verification) {
            let beforeCriteria = plan.successCriteria
            let beforeSuggestions = plan.suggestedDecisions
            let issues = PromptQuality.repair(&plan, analysis: analysis, context: context)
            if !issues.isEmpty { trace.add("quality", "repaired-locally", issues.joined(separator: "; ")) }
            for issue in issues where issue.hasPrefix("diagnostic covered by task:") || issue.hasPrefix("near-duplicate:") {
                trace.add("quality", "removed", issue)
            }
            for removed in beforeCriteria where !plan.successCriteria.contains(removed) {
                trace.add("quality", "removed", "success criterion: \(removed) (replaced with observable request-derived checks where available)")
            }
            for removed in beforeSuggestions where !plan.suggestedDecisions.contains(removed) {
                trace.add("quality", "removed", "suggestion: \(removed) (subjective, generic, unsupported, or redundant)")
            }
        }
        if plan.provider != "local", let guidance = plan.guidance, guidance.kind == .create {
            let approach = guidance.goodLooksLike
            var alreadyCovered = plan.confirmedRequirements
            alreadyCovered.append(contentsOf: plan.constraints)
            alreadyCovered.append(contentsOf: plan.tasks.map { "\($0.title) \($0.detail)" })
            alreadyCovered.append(contentsOf: plan.successCriteria)
            alreadyCovered.append(contentsOf: plan.verificationInstructions)
            if let objective = modelPlan?.objective { alreadyCovered.append(objective) }
            var suggestions = plan.suggestedDecisions
            for item in approach where !(alreadyCovered + suggestions).contains(where: { existing in
                Self.semanticallySimilar(item, existing)
                    || (Self.groundedWordCoverage(item, existing) >= 0.75 && Self.groundedWordCoverage(existing, item) >= 0.75)
            }) {
                suggestions.append(item)
            }
            plan.suggestedDecisions = suggestions
            let hasInspection = plan.tasks.contains { task in
                (task.title + " " + task.detail).range(of: #"(?i)\b(locate|find|inspect|review|check|identify|look for)\b"#, options: .regularExpression) != nil
            }
            if !hasInspection, let first = guidance.investigate.first {
                var id = "create_inspect"
                while plan.tasks.contains(where: { $0.id == id }) { id += "_" }
                plan.tasks.insert(PlanTask(id: id, title: first), at: 0)
            }
            plan.tasks = PromptQuality.normalizeDependencies(plan.tasks)
            trace.add("guidance", "merged", "added create playbook suggestions to the model plan")
        }
        trace.add("composition", "input", "tasks=\(plan.tasks.count), verification=\(plan.verificationInstructions.count)")


        // 8: construction.
        let modelRole = modelPlan?.role.trimmingCharacters(in: .whitespacesAndNewlines)
        let role = modelRole.flatMap { value -> String? in
            value.range(of: #"(?is)^You are\b.+[.!?]$"#, options: .regularExpression) != nil ? value : nil
        } ?? Self.defaultRole(context)
        var objective = Playbook.underspecified(analysis) != nil ? analysis.intent : (modelPlan?.objective ?? analysis.intent)
        if guidance != nil, modelPlan == nil {
            if let preface = objective.range(of: #"^.*?\bprompt\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) {
                objective = String(objective[preface.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                objective = objective.prefix(1).uppercased() + objective.dropFirst()
            }
            if guidance?.kind == .create { objective = Playbook.createObjective(analysis.text, direction: guidance?.direction) }
            objective += objective.hasSuffix(".") ? "" : "."
            if let direction = guidance?.direction, guidance?.kind != .create {
                objective += " The user wants it to feel \(direction); the target quality below is derived from that."
            } else if guidance?.kind == .diagnose {
                objective += " The request does not say what exactly is wrong, so first establish that, then fix it."
            } else if guidance?.kind != .create {
                objective += " Unspecified details are open; follow existing product patterns and state any important choice."
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
        trace.add("composition", "rendered", "characters=\(prompt.count), tasks=\(plan.tasks.count)")
        plan.optimizedPrompt = prompt
        plan.notices = notices
        plan.trace = trace
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
        // Small models sometimes copy a rule from the prompt into a list. Those lines say nothing about the user's task.
        func notRuleEcho(_ item: String) -> Bool { !Self.isInstructionEcho(item) }
        func repeatsObservedSymptom(_ item: String) -> Bool {
            let marker = #"(?i)\b(slow|lag|freeze|frozen|unresponsive|doesn'?t work|doesnt work|not responding|buggy|bugs?|fails?|failure|crashes?|intermittent|time ?outs?)\b"#
            return SemanticValidator.clauses(item).contains { clause in
                clause.range(of: marker, options: .regularExpression) != nil
                    && Self.groundedWordCoverage(clause, analysis.text) >= 0.55
            }
        }
        m.confirmedRequirements = m.confirmedRequirements.filter(notRuleEcho)
        m.confirmedRequirements.removeAll(where: repeatsObservedSymptom)
        m.suggestedDecisions = m.suggestedDecisions.filter(notRuleEcho)
        m.constraints = m.constraints.filter(notRuleEcho)
        m.successCriteria = m.successCriteria.filter(notRuleEcho)
        m.verificationSteps = m.verificationSteps.filter(notRuleEcho)
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
        // When the whole request is one sentence containing a constraint, the analyzer returns that entire sentence. Once the model
        // has split it into atomic constraints, the restated request adds nothing.
        func sameConstraint(_ lhs: String, _ rhs: String) -> Bool {
            if semanticallySimilar(lhs, rhs) { return true }
            let left = SemanticValidator.directives(in: lhs)
            let right = SemanticValidator.directives(in: rhs)
            if left.count == 1, right.count == 1,
               left[0].kind == right[0].kind, left[0].verb == right[0].verb {
                let ignored: Set<String> = ["a", "an", "the"]
                let a = Set(left[0].objectText.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)).subtracting(ignored)
                let b = Set(right[0].objectText.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)).subtracting(ignored)
                if !a.isEmpty, !b.isEmpty,
                   Double(a.intersection(b).count) / Double(max(a.count, b.count)) >= 0.65 { return true }
            }
            return groundedWordCoverage(lhs, rhs) >= 0.75 && groundedWordCoverage(rhs, lhs) >= 0.75
        }
        let focusedAnalysisConstraints = analysis.constraints.filter { c in
            !m.constraints.contains { sameConstraint(c, $0) }
                && !(groundedWordCoverage(analysis.text, c) >= 0.9 && groundedWordCoverage(c, analysis.text) >= 0.9)
        }
        let groundedModelConstraints = m.constraints.filter { candidate in
            grounded(candidate) && !focusedAnalysisConstraints.contains { sameConstraint(candidate, $0) }
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
            tasks: PromptQuality.normalizeDependencies(m.tasks.map { PlanTask(id: $0.id, title: $0.title, detail: $0.detail, dependsOn: $0.dependsOn) }),
            constraints: nonRedundant(dedupe(focusedAnalysisConstraints + groundedModelConstraints), against: confirmed),
            successCriteria: groundedCriteria,
            missingInformation: m.missingInformation,
            confirmedRequirements: dedupe(userConfirmed + additionalConfirmed),
            suggestedDecisions: nearExactRedundant(m.suggestedDecisions + optionalModelConstraints + optionalModelRequirements + optionalModelCriteria,
                                                   against: confirmed + taskText + analysis.constraints),
            plannedComponents: (m.plannedComponents ?? []).enumerated().map { i, p in
                PlannedComponent(id: "p\(i + 1)", name: p.name, type: ComponentType(rawValue: p.type) ?? .library, connectsTo: p.connectsTo.filter(componentIDs.contains))
            },
            verificationInstructions: m.verificationSteps)
    }

    /// The offline plan: everything here comes from the request text and the analyzer, nothing invented.
    static func localPlan(analysis: RequestAnalysis, context: RetrievedContext, quick: Bool = false) -> PromptPlan {
        if quick, analysis.taskType != .feature, let recipe = QuickRecipes.recipe(for: analysis) {
            return PromptPlan(originalPrompt: analysis.text, intent: analysis.intent, taskType: analysis.taskType, tasks: recipe.tasks,
                              constraints: analysis.constraints, successCriteria: recipe.successCriteria,
                              confirmedRequirements: dedupe(analysis.confirmedRequirements), suggestedDecisions: recipe.suggestions,
                              verificationInstructions: recipe.verification)
        }
        if analysis.complexity < 2 && !quick && analysis.taskType != .feature {
            return PromptPlan(originalPrompt: analysis.text, intent: analysis.intent, taskType: analysis.taskType,
                              constraints: analysis.constraints, confirmedRequirements: dedupe(analysis.confirmedRequirements))
        }
        let refs = context.components.prefix(5).map { CodeReference(path: $0.path, symbol: nil, reason: "\($0.type) module matching the request", source: .graph) }
        let tasks: [PlanTask]
        switch analysis.taskType {
        case .feature:
            let detail = analysis.text.range(of: #"(?i)\b(?:hover|cursor|pointer)\w*\b"#, options: .regularExpression) != nil
                ? "Hover over each affected control, then tab through each one and verify equivalent visible focus feedback."
                : "Check the existing patterns and look for similar behavior."
            tasks = [PlanTask(id: "t1", title: "Inspect where the feature belongs", detail: detail),
                     PlanTask(id: "t2", title: "Implement the requested feature", detail: "Honor the user's stated details and fit the existing product.", dependsOn: ["t1"]),
                     PlanTask(id: "t3", title: "Verify the behavior", detail: "Check it manually or with project tests if available.", dependsOn: ["t2"])]
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
        case .feature: Self.featureCriteria(context, request: analysis.text)
        default: ["The requested behavior works as described.", "Existing tests and the build pass."]
        }
        var verification: [String] = []
        if analysis.taskType == .feature, analysis.text.range(of: #"(?i)\b(?:hover|cursor|pointer)\w*\b"#, options: .regularExpression) != nil {
            verification.append("Hover over each affected control, then tab through each one and verify equivalent visible focus feedback.")
        }
        if contextShowsBuildOrTestSetup(context) {
            verification += ["Run the existing tests for the affected code.", "Run the build or type checker."]
        }
        return PromptPlan(originalPrompt: analysis.text, intent: analysis.intent, taskType: analysis.taskType, codeReferences: refs, tasks: tasks,
                          constraints: analysis.constraints, successCriteria: criteria, confirmedRequirements: dedupe(analysis.confirmedRequirements),
                          verificationInstructions: dedupe(verification))
    }

    private static func contextShowsBuildOrTestSetup(_ context: RetrievedContext) -> Bool {
        let paths = context.components.flatMap { [$0.path] + $0.files }.map { $0.lowercased() }
        return paths.contains { path in
            let name = URL(fileURLWithPath: path).lastPathComponent
            return ["package.json", "package.swift", "makefile", "justfile", "pyproject.toml", "cargo.toml", "go.mod", "build.gradle", "pom.xml"].contains(name)
                || name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace")
                || name.hasSuffix("test.swift") || name.hasSuffix("tests.swift") || name.hasSuffix(".test.ts") || name.hasSuffix(".spec.ts")
        }
    }

    private static func featureCriteria(_ context: RetrievedContext, request: String) -> [String] {
        var criteria = PromptQuality.observableVisualCriteria(for: request)
        if criteria.isEmpty { criteria = ["The requested feature works as described."] }
        if contextShowsBuildOrTestSetup(context) { criteria.append("Existing tests and the build pass.") }
        return criteria
    }

    static func isInstructionEcho(_ item: String) -> Bool {
        let l = item.lowercased()
        return ["do not invent", "don't invent", "never invent", "use only paths", "only paths from", "paths from the context", "do not ask question",
                "don't ask question", "no user input", "do not guess", "omit empty", "omit keys", "json object", "untrusted", "from the request and the context",
                "do not return", "missinginformation"].contains { l.contains($0) }
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

    private static func nearExactRedundant(_ items: [String], against reference: [String]) -> [String] {
        var kept: [String] = []
        for item in items where !(reference + kept).contains(where: { existing in
            let forward = groundedWordCoverage(item, existing)
            let reverse = groundedWordCoverage(existing, item)
            return item.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(existing.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
                || (forward >= 0.9 && reverse >= 0.9)
        }) { kept.append(item) }
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
