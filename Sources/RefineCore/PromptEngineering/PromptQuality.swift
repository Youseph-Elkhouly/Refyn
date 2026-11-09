import Foundation

/// A local quality gate. Engineering methods are proposals, never additional user requirements.
/// No inference, repository reads, or numeric performance targets.
public enum PromptQuality {
    public static func needsGuidance(_ analysis: RequestAnalysis) -> Bool {
        if QuickRecipes.recipe(for: analysis) != nil { return false }
        return [.performance, .refactor, .investigation].contains(analysis.taskType) || analysis.complexity >= 2 || analysis.text.range(
            of: #"(?i)\b(buggy|bug|slow|weird|breaking|secure|better|refactor|clean up|forever)\b"#,
            options: .regularExpression) != nil
    }

    public static func genericCriterion(_ text: String) -> Bool {
        text.range(of: #"(?i)works? (properly|correctly|as described)|performs? smoothly|no new bugs|everything is tested|confirmed by a test or inspection|responsive and.*smooth|runs smoothly|runs? faster and more reliably|function.*(correctly|as expected)|\b(?:everything|all (?:features|functionality|issues|bugs))\b.*(?:work|test|fix|function)|(?:is|are) (?:cleaner|more maintainable)|handled correctly|\bis stable\b|more (?:readable|maintainable)|within (?:expected|acceptable|reasonable)|no (?:recurring|unexplained|new performance)|stable and performs well|work as intended|without bugs|no.*(bugs|issues).*introduced|reported problem no longer occurs|under (various|different) conditions|any new bugs|issues? (are |is |have been )?(resolved|fixed)|quality.*improved|function.*as (intended|expected)|all states.*visually (?:distinct|consistent)|ui elements?.*(?:consistent|improved)|interactive states?.*(?:clear|feedback)|accessibility guidelines? (?:are )?respected|accessible and compliant|functional and intuitive|subtle interaction feedback for all states|accessibility compliance for all ui states|consistent use of design tokens|improved visual hierarchy and spacing|no regressions in (?:existing )?(?:ui|behavior)|(?:animation|animations) (?:are |feel )?(?:smooth|consistent|natural)|(?:animation )?timing and easing.*adjusted|animations? (?:respect user motion preferences|do not interfere with accessibility)|no interference with user focus or accessibility|consistent animation timing across all interactions|no abrupt or jarring transitions|interactions? (?:are )?not disrupted by animations|monitoring tools? detect and alert|error logs? show no recurring|error logs? show no patterns or trends|(?:api|database operations?) (?:is |are )?stable|(?:api|database operations?).*within (?:expected|acceptable|reasonable)|existing interactions? .*still work|each fixed problem .*no longer occurs|regression tests? pass successfully|code is free of redundancies|follows? best practices|documentation is accurate and complete|performance improvements? (?:are )?measurable and consistent|no long-running transactions or locks|improved query performance and reduced execution time|the app (?:runs|is) (?:faster|more reliably)"#,
                   options: .regularExpression) != nil
    }

    private static func hasInvestigation(_ plan: PromptPlan) -> Bool {
        plan.tasks.contains { ($0.title + " " + $0.detail).range(
            of: #"(?i)\b(locate|inspect|reproduce|measure|trace|baseline|profile|review|map|examine|identify)\b"#,
            options: .regularExpression) != nil }
    }

    /// Convert reported symptoms into observable checks without copying vague phrases such as "works properly"
    /// into acceptance criteria. The original wording remains available in the investigation guidance.
    private static func observableChecks(for symptom: String) -> [String] {
        let text = symptom.lowercased()
        func has(_ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
        var checks: [String] = []

        if has(#"\b(slow|sluggish|laggy|lagging|forever|takes .*to)\b"#) {
            checks.append("Repeat the reported slow operation under the same conditions after the fix and record the result.")
        }
        if has(#"\b(button|control)s?\b"#) && has(#"\b(don'?t respond|doesn'?t respond|doesnt respond|unresponsive|not responding|not work|doesn'?t work|doesnt work|fail)\b"#) {
            checks.append("Repeat the affected button actions after the fix and confirm they respond in the same scenarios.")
        }
        if has(#"\b(ui|interface|app)\b"#) && has(#"\b(freez|hang|unresponsive|not responding)\w*\b"#) {
            checks.append("Repeat the scenario that previously froze the interface and confirm it stays interactive throughout.")
        }
        if has(#"\b(buggy|bugs?|break(?:s|ing)?|fail(?:s|ure|ures|ing)?|crash(?:es|ed)?|intermittent)\b"#) {
            checks.append("Repeat the reproduction that exposed the reported failure after the change and report any failure that still reproduces.")
        }
        if has(#"\b(doesn'?t work|doesnt work|not work|not working|some stuff|some things)\b"#) {
            checks.append("Retest each interaction reported as not working and report any failure that still reproduces.")
        }
        if checks.isEmpty {
            checks.append("Reproduce the reported behavior before the change, then repeat the same steps and report any remaining failure.")
        }
        return checks
    }

    public static func issues(_ plan: PromptPlan, analysis: RequestAnalysis) -> [String] {
        guard needsGuidance(analysis) else { return [] }
        var issues: [String] = []
        if plan.tasks.count < 2 || !hasInvestigation(plan) { issues.append("missing execution strategy") }
        if plan.verificationInstructions.isEmpty { issues.append("missing verification") }
        if plan.successCriteria.isEmpty || plan.successCriteria.contains(where: genericCriterion) { issues.append("weak acceptance criteria") }
        if Set(plan.confirmedRequirements.map { $0.lowercased() }).count < plan.confirmedRequirements.count { issues.append("duplicate requirements") }
        return issues
    }

    @discardableResult
    public static func repair(_ plan: inout PromptPlan, analysis: RequestAnalysis, context: RetrievedContext? = nil) -> [String] {
        guard needsGuidance(analysis) else { return [] }
        let findings = issues(plan, analysis: analysis)
        let sources = ([analysis.searchText] + (context.map { InventionGuard.sources(analysis: analysis, context: $0) } ?? [])).joined(separator: "\n")
        func unsupportedMetric(_ text: String) -> Bool {
            guard let regex = try? NSRegularExpression(pattern: #"(?i)\b\d+(?:[.–-]\d+)?\s*(?:ms|milliseconds?|seconds?|fps|%)"#) else { return false }
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).contains {
                guard let range = Range($0.range, in: text) else { return false }
                return !sources.localizedCaseInsensitiveContains(String(text[range]))
            }
        }
        plan.successCriteria.removeAll { genericCriterion($0) || unsupportedMetric($0) }
        plan.verificationInstructions.removeAll { genericCriterion($0) || unsupportedMetric($0) }
        plan.suggestedDecisions.removeAll { genericCriterion($0) || unsupportedMetric($0) }
        for index in plan.tasks.indices {
            if unsupportedMetric(plan.tasks[index].title) { plan.tasks[index].title = "Verify the measured outcome" }
            if unsupportedMetric(plan.tasks[index].detail) {
                plan.tasks[index].detail = "Compare the same scenario before and after; confirm a numerical target with the user if needed."
            }
        }
        // The local builder's stand-ins say nothing about this request; the task-specific strategy below replaces them.
        plan.tasks.removeAll { ["implement the change", "inspect the affected code", "cover it with tests"].contains($0.title.lowercased()) }
        let request = analysis.searchText.lowercased()
        func has(_ pattern: String) -> Bool { request.range(of: pattern, options: .regularExpression) != nil }
        let refactor = analysis.taskType == .refactor || has(#"clean up.*code|refactor"#)
        // "without breaking anything" is a constraint on a refactor, not a bug report.
        let debugging = !refactor && (analysis.taskType == .bugfix || has(#"bug|break|weird|doesnt work|doesn't work|not work"#))
        let performance = analysis.taskType == .performance || has(#"slow|forever|performance|latency"#)
        let motion = has(#"animat|transition|opening|closing"#)
        let security = has(#"secur|login|authentic"#)
        let ui = analysis.taskType == .ui || has(#"\bui\b|design|visual"#)
        var symptomClauses = SemanticValidator.clauses(analysis.text).filter { clause in
            clause.range(of: #"(?i)\b(slow|lag|freeze|frozen|unresponsive|don't respond|dont respond|doesn't respond|doesnt respond|doesn't work|doesnt work|not responding|buggy|bugs?|breaks?|breaking|fails?|failure|crashes?|intermittent|takes .*to open|switch(?:ing|es)? views?|open(?:ing)? (?:the )?(?:window|view|interface)|close(?:ing)? (?:the )?(?:window|view|interface))\b"#, options: .regularExpression) != nil
        }
        if has(#"\bui freezes\b"#), !symptomClauses.contains(where: { $0.localizedCaseInsensitiveContains("UI freezes") }) {
            symptomClauses.append("UI freezes")
        }
        for clause in symptomClauses {
            let target = "Investigate the reported behavior: \(clause)."
            if !plan.suggestedDecisions.contains(where: { PromptOptimizer.semanticallySimilar($0, target) }) { plan.suggestedDecisions.append(target) }
        }
        if has(#"freeze|frozen|unresponsive|not responding|ui hangs|interface hangs"#) {
            plan.suggestedDecisions.append("If the interface freezes, check for synchronous work or blocking operations on the main thread.")
        }
        let asksToFix = has(#"\b(?:fix|repair|resolve)\b"#)
        func isFixStep(_ title: String) -> Bool { title.range(of: #"(?i)\b(?:fix|fixes|resolve|repair|correct|address)\b"#, options: .regularExpression) != nil }

        // A vague request authorizes finding out what is wrong, not a chosen remedy. A concrete request ("add retry", a named
        // symbol, a stated condition) has already said what it wants, so its implementation tasks stand.
        let vague = analysis.keyTerms.isEmpty && !analysis.hasConditions && SemanticValidator.requestedAddition(in: analysis.searchText) == nil
        var candidates: [String] = []
        let remedy = #"(?i)^(?:add|integrate|introduce|enforce|replace|enable|implement|encrypt|update|upgrade|adopt|migrate|regularly)\b"#
        func prescribes(_ text: String) -> Bool { text.range(of: remedy, options: .regularExpression) != nil }
        func removeTasks(where shouldRemove: (PlanTask) -> Bool) {
            let removed = plan.tasks.filter(shouldRemove)
            guard !removed.isEmpty else { return }
            candidates += removed.map(\.title)
            let inherited = Dictionary(uniqueKeysWithValues: removed.map { ($0.id, $0.dependsOn) })
            plan.tasks.removeAll { inherited[$0.id] != nil }
            for index in plan.tasks.indices {
                // A dependent inherits what the removed task depended on, so the order stays coherent.
                plan.tasks[index].dependsOn = PromptOptimizer.dedupe(plan.tasks[index].dependsOn.flatMap { inherited[$0] ?? [$0] }.filter { inherited[$0] == nil })
            }
        }
        if Playbook.underspecified(analysis) != nil {
            // A task can read like a review ("Validate inputs") while its detail changes the code ("Update validation rules").
            removeTasks { !(asksToFix && isFixStep($0.title)) && (!Lex.isObservation($0.title) || prescribes($0.detail)) }
            candidates += plan.suggestedDecisions.filter(prescribes)
            plan.suggestedDecisions.removeAll(where: prescribes)
            plan.successCriteria = ["Each proposed change identifies an observed problem and evidence; unresolved policy decisions are explicitly reported."]
            plan.verificationInstructions = ["Inspect existing behavior and policy before choosing checks; verify confirmed changes against that baseline and report actual results."]
        } else if vague, [.other, .ui, .performance, .bugfix].contains(analysis.taskType) {
            removeTasks { !isFixStep($0.title) && prescribes($0.title) && !Lex.isObservation($0.title) && PromptOptimizer.groundedWordCoverage($0.title, analysis.searchText) < 0.35 }
        }
        if !candidates.isEmpty {
            var unique: [String] = []
            for candidate in candidates where !unique.contains(where: { PromptOptimizer.groundedWordCoverage($0, candidate) >= 0.5 || PromptOptimizer.groundedWordCoverage(candidate, $0) >= 0.5 }) { unique.append(candidate) }
            plan.suggestedDecisions.append("Consider only if the investigation finds a matching problem; none of these is requested: " + unique.prefix(4).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .")) }.joined(separator: "; ") + ".")
        }
        plan.constraints = PromptOptimizer.dedupe(plan.constraints)
        plan.confirmedRequirements = PromptOptimizer.dedupe(plan.confirmedRequirements)
        var strategy: [(String, String)]
        if refactor {
            strategy = [("Map behavior and callers", "Identify responsibilities, callers and existing coverage before restructuring."),
                        ("Refactor in reviewable changes", "Keep observable behavior and supported interfaces identical; compare results with the baseline.")]
        } else if debugging {
            strategy = [("Locate and reproduce", "Inspect the existing implementation; record reproducible symptoms, triggers, and expected versus observed behavior."),
                        ("Trace the root cause", "Follow the failing path and collect evidence before choosing a fix."),
                        ("Fix confirmed issues", "Make focused changes for reproduced problems; report issues that could not be reproduced.")]
        } else if performance {
            strategy = [("Establish a baseline", "Reproduce the slow operation with representative inputs and measure elapsed time and resource use."),
                        ("Profile before changing code", "Identify the measured bottleneck, make a focused improvement, and repeat the same measurement.")]
        } else if security {
            strategy = [("Review the existing security boundary", "Inspect the current login flow, trust boundaries and failure handling; identify demonstrable weaknesses."),
                        ("Address confirmed weaknesses", "Use the project's existing mechanisms; propose policy changes for confirmation rather than choosing them silently.")]
        } else if ui {
            strategy = [("Inspect the current interface", "Identify concrete usability or visual issues in representative states and confirm the intended scope."),
                        ("Apply focused refinements", "Use existing design conventions and components; justify each change by an observed issue.")]
        } else if analysis.taskType == .investigation {
            strategy = [("Trace the relevant implementation", "Gather evidence from the actual code and reproduce the reported behavior."),
                        ("Report findings", "Separate confirmed findings from hypotheses and recommend next steps with supporting evidence.")]
        } else if analysis.taskType == .test {
            strategy = [("Map scenarios to behavior", "Inspect the implementation and existing tests to establish expected outcomes."),
                        ("Cover meaningful cases", "Add targeted assertions for the requested scenarios, including boundary and failure cases where relevant.")]
        } else {
            strategy = [("Inspect integration points", "Read the relevant implementation and existing conventions; resolve discoverable details from the code."),
                        ("Implement the requested behavior", "Keep changes scoped to the request; flag unresolved product decisions instead of assuming them.")]
        }
        if plan.tasks.count < 2 || !hasInvestigation(plan) {
            let existing = plan.tasks.map { $0.title + " " + $0.detail }.joined(separator: " ").lowercased()
            for (index, step) in strategy.enumerated() where !existing.contains(step.0.lowercased()) {
                var id = "quality\(index)"
                while plan.tasks.contains(where: { $0.id == id }) { id += "_" }
                plan.tasks.append(PlanTask(id: id, title: step.0, detail: step.1))
            }
        }
        // The user asked for a fix, so the plan must contain one even when the model only wrote investigation steps.
        if asksToFix, !plan.tasks.contains(where: { isFixStep($0.title) }) {
            let step = PlanTask(id: "quality_fix", title: "Fix confirmed issues", detail: "Make the smallest change that addresses each reproduced problem; report anything that could not be reproduced.")
            let at = plan.tasks.firstIndex { $0.title.range(of: #"(?i)\b(?:test|tests|verify|validate)\b"#, options: .regularExpression) != nil } ?? plan.tasks.endIndex
            plan.tasks.insert(step, at: at)
        }
        // Investigation comes before changes. Only tasks with no dependencies move, so a stated order is never broken.
        let investigationFirst = #"(?i)^(?:locate|find|inspect|review|map|establish|reproduce|trace)\b"#
        let early = plan.tasks.filter { $0.dependsOn.isEmpty && $0.title.range(of: investigationFirst, options: .regularExpression) != nil }
        plan.tasks = early + plan.tasks.filter { t in !early.contains { $0.id == t.id } }

        var investigations: [String] = []
        if motion {
            investigations.append("Inspect transition timing and state changes; exercise interruptions and rapid reversals. Check focus and lifecycle handling if the transition opens or closes a window.")
        }
        var observedChecks = PromptOptimizer.dedupe(symptomClauses.flatMap(observableChecks(for:)))
        if refactor { observedChecks.removeAll { $0.contains("reported failure") } }
        let hasSpecificFailureCheck = observedChecks.contains { $0.contains("button actions") || $0.contains("interactions reported as not working") || $0.contains("froze the interface") }
        if hasSpecificFailureCheck {
            observedChecks.removeAll { $0.contains("reproduction that exposed the reported failure") }
        }
        for criterion in observedChecks {
            if plan.successCriteria.count < 6 && !plan.successCriteria.contains(where: { PromptOptimizer.semanticallySimilar($0, criterion) }) {
                plan.successCriteria.append(criterion)
            }
        }
        if performance {
            investigations.append("Profile the reported slow path before changing it; compare the same scenario before and after and report measurements without inventing a target.")
        }
        if has(#"\bapi\b"#) { investigations.append("Trace a failing request through validation, handling and response generation; inspect error evidence before changing response behavior.") }
        if has(#"database|query"#) { investigations.append("Inspect slow queries, access patterns and contention using available diagnostics; choose changes from measured evidence.") }
        if security { investigations.append("Check successful and rejected sign-in attempts and access boundaries against existing policy; avoid introducing an unrequested authentication mechanism.") }
        plan.suggestedDecisions = PromptOptimizer.dedupe(plan.suggestedDecisions + investigations)
        if !plan.verificationInstructions.contains(where: { $0.range(of: #"(?i)run.*(?:tests|build|type checker)"#, options: .regularExpression) != nil }) {
            plan.verificationInstructions.append("Run the relevant existing tests and build; report commands, results and checks that could not run.")
        }
        if debugging {
            let step = "Replay each reproduced failure after the fix and exercise adjacent existing interactions; distinguish automated regression coverage from manual observations."
            if !plan.verificationInstructions.contains(step) { plan.verificationInstructions.append(step) }
        }
        // Observable, task-specific outcomes replace the stock lines removed above. Added only up to a small total, so a good model answer is not padded.
        var outcomes: [String] = []
        if motion {
            outcomes.append("Each transition completes without visible snapping or unexpected state changes.")
        }
        if refactor { outcomes.append("Representative inputs produce the same observable outputs before and after restructuring.") }
        if performance { outcomes.append("Before-and-after measurements use the same workload, with observed changes and tradeoffs reported.") }
        if security { outcomes.append("Each implemented security change addresses a weakness supported by evidence and is checked against the existing sign-in policy.") }
        if ui { outcomes.append("The before-and-after comparison verifies the specific visual issues identified in the current interface without changing unrelated behavior.") }
        if analysis.taskType == .investigation { outcomes.append("Findings are supported by code or runtime evidence, and unresolved causes are labeled as unknown.") }
        for outcome in outcomes where plan.successCriteria.count < 5 && !plan.successCriteria.contains(outcome) { plan.successCriteria.append(outcome) }
        if ui && has(#"don't|dont|do not|without|keep|preserve"#) {
            plan.verificationInstructions.append("Compare the affected interface before and after to verify the user's visual constraints.")
        }
        let preservedTargets = SemanticValidator.directives(in: analysis.searchText).filter { $0.kind == .preserve }.map(\.objectText)
        var preservedTargetsSeen = Set<String>()
        plan.successCriteria = PromptOptimizer.dedupe(plan.successCriteria).filter { criterion in
            let preservesBehavior = criterion.range(of: #"(?i)\b(unchanged|identical|same (?:observable )?(?:outputs?|behavior)|preserv(?:e|ed)|without (?:changing|breaking)|no regressions?)\b"#, options: .regularExpression) != nil
            guard preservesBehavior else { return true }
            guard let target = preservedTargets.first(where: { PromptOptimizer.groundedWordCoverage($0, criterion) >= 0.5 }) else { return true }
            guard preservedTargetsSeen.insert(target.lowercased()).inserted else { return false }
            return true
        }
        plan.verificationInstructions = PromptOptimizer.dedupe(plan.verificationInstructions)
        return findings
    }
}
