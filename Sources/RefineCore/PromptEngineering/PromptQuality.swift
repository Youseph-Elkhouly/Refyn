import Foundation

/// A local quality gate. Engineering methods are proposals, never additional user requirements.
/// No inference, repository reads, or numeric performance targets.
public enum PromptQuality {
    private enum TaskRole { case investigation, implementation, verification, other }

    /// Retain genuine prerequisite links, but don't turn several independent observations into a serial checklist.
    /// Findings precede implementation; verification follows implementation.
    static func normalizeDependencies(_ tasks: [PlanTask]) -> [PlanTask] {
        func role(_ task: PlanTask) -> TaskRole {
            let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.range(of: #"(?i)^(?:test|verify|validate|retest|run (?:the )?(?:tests?|build|checks?)|compare (?:the )?(?:same|before))\b|\bregression tests?\b"#, options: .regularExpression) != nil {
                return .verification
            }
            if title.range(of: #"(?i)^(?:locate|find|inspect|review|map|establish|reproduce|trace|collect|gather|investigate|profile|measure|monitor|check|examine|identify|analy[sz]e|diagnose|audit|read|capture|record)\b"#, options: .regularExpression) != nil {
                return .investigation
            }
            if title.range(of: #"(?i)^(?:fix|implement|add|change|update|replace|refactor|remove|create|introduce|optimi[sz]e|address|resolve|apply|migrate|modify|configure|use|enable|disable)\b"#, options: .regularExpression) != nil {
                return .implementation
            }
            return .other
        }
        let roles = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, role($0)) })
        let investigationIDs = tasks.filter { role($0) == .investigation }.map(\.id)
        let implementationIDs = tasks.filter { role($0) == .implementation }.map(\.id)
        let ids = Set(tasks.map(\.id))
        return tasks.map { original in
            var task = original
            var dependencies = PromptOptimizer.dedupe(task.dependsOn).filter { $0 != task.id && ids.contains($0) }
            switch role(task) {
            case .investigation:
                dependencies.removeAll { roles[$0] == .investigation || roles[$0] == .implementation || roles[$0] == .verification }
            case .implementation:
                // Rebuild diagnostic prerequisites in stable task order. Keeping an arbitrary
                // subset first can produce duplicates and misleading numbered references.
                dependencies.removeAll { roles[$0] != .implementation && roles[$0] != .other }
                for id in investigationIDs where id != task.id && !dependencies.contains(id) { dependencies.append(id) }
            case .verification:
                dependencies.removeAll { roles[$0] != .implementation && roles[$0] != .other }
                for id in implementationIDs where id != task.id && !dependencies.contains(id) { dependencies.append(id) }
            case .other:
                break
            }
            task.dependsOn = dependencies
            return task
        }
    }

    public static func needsGuidance(_ analysis: RequestAnalysis) -> Bool {
        if QuickRecipes.recipe(for: analysis) != nil { return false }
        return [.performance, .refactor, .investigation].contains(analysis.taskType) || analysis.complexity >= 2 || analysis.text.range(
            of: #"(?i)\b(buggy|bug|slow|weird|breaking|secure|better|refactor|clean up|forever)\b"#,
            options: .regularExpression) != nil
    }

    public static func genericCriterion(_ text: String) -> Bool {
        if text.range(of: #"(?i)\bno\s+(?:new\s+)?(?:issues?|problems?|bugs?)\b(?:\s+or\s+(?:new\s+)?(?:issues?|problems?|bugs?|regressions?))?(?:\s+in\s+(?:existing\s+)?(?:functionality|behavior))?"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"(?i)\b(?:opens?|loads?|responds?)\s+(?:quickly|promptly)\b|\b(?:switch(?:ing)?|transitions?)\b.{0,35}\b(?:smooth|smoothly|seamlessly)\b"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"(?i)\btoggled?\s+(?:on and off\s+)?smoothly\b"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"(?i)\bno\s+(?:api|interface)\s+changes?\b(?:.*\b(?:functional(?:ity)?\s+)?(?:regressions?|breaks?)\b)?|\bno\s+(?:functional(?:ity)?\s+)?regressions?\b"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"(?i)\b(?:api|database operations?)\b.*\b(?:consistent|reliable|stable|performant)\b.*\b(?:under (?:concurrent )?(?:load|users?)|with(?:out)? (?:errors|timeouts)|works? as expected)\b"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"(?i)\b(?:significantly|substantially|noticeably|much)\s+faster\b|\b(?:significantly|substantially|noticeably)\s+(?:improved|quicker)\b"#,
                      options: .regularExpression) != nil { return true }
        if text.range(of: #"(?i)\ball (?:ui )?elements? (?:are )?(?:styled|rendered|displayed) correctly\b|\bno new errors? or failures?\b"#, options: .regularExpression) != nil { return true }
        return text.range(of: #"(?i)works? (properly|correctly|as described)|performs? smoothly|no new bugs|everything is tested|confirmed by a test or inspection|responsive and.*smooth|runs smoothly|runs? faster and more reliably|function.*(correctly|as expected)|\b(?:everything|all (?:features|functionality|issues|bugs))\b.*(?:work|test|fix|function)|(?:is|are) (?:cleaner|more maintainable)|handled correctly|\bis stable\b|more (?:readable|maintainable)|within (?:expected|acceptable|reasonable)|no (?:recurring|unexplained|new performance)|stable and performs well|work as intended|without bugs|no.*(bugs|issues).*introduced|reported problem no longer occurs|under (various|different) conditions|any new bugs|issues? (are |is |have been )?(resolved|fixed)|quality.*improved|function.*as (intended|expected)|all states.*visually (?:distinct|consistent)|ui elements?.*(?:consistent|improved)|interactive states?.*(?:clear|feedback)|accessibility guidelines? (?:are )?respected|accessible and compliant|functional and intuitive|subtle interaction feedback for all states|accessibility compliance for all ui states|consistent use of design tokens|improved visual hierarchy and spacing|no regressions in (?:existing )?(?:ui|behavior)|(?:animation|animations) (?:are |feel )?(?:smooth|consistent|natural)|(?:animation )?timing and easing.*adjusted|animations? (?:respect user motion preferences|do not interfere with accessibility)|no interference with user focus or accessibility|consistent animation timing across all interactions|no abrupt or jarring transitions|interactions? (?:are )?not disrupted by animations|monitoring tools? detect and alert|error logs? show no recurring|error logs? show no patterns or trends|(?:api|database operations?) (?:is |are )?stable|(?:api|database operations?).*within (?:expected|acceptable|reasonable)|existing interactions? .*still work|each fixed problem .*no longer occurs|regression tests? pass successfully|code is free of redundancies|follows? best practices|documentation is accurate and complete|performance improvements? (?:are )?measurable and consistent|no long-running transactions or locks|improved query performance and reduced execution time|the app (?:runs|is) (?:faster|more reliably)|\bno (?:database )?timeouts? (?:occur|happen)s?\b(?:.*\bunder (?:concurrent|parallel) load\b)?|\bno (?:api|interface) changes? or (?:functional(?:ity)? )?regressions?\b|\b(?:consistent,?\s*)?(?:reliable|stable)(?:,?\s*and)?\s*(?:performant|fast)\b"#,
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
        if has(#"\btime\s?outs?\b"#) && has(#"\b(concurren|simultaneous|multiple users|under load)\w*\b"#) {
            checks.append("Repeat the reported concurrent workload and confirm the same timeout no longer occurs.")
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
        guard needsGuidance(analysis) || plan.successCriteria.contains(where: genericCriterion) else { return [] }
        var issues: [String] = []
        if plan.tasks.count < 2 || !hasInvestigation(plan) { issues.append("missing execution strategy") }
        if plan.verificationInstructions.isEmpty { issues.append("missing verification") }
        if plan.successCriteria.isEmpty || plan.successCriteria.contains(where: genericCriterion) { issues.append("weak acceptance criteria") }
        if Set(plan.confirmedRequirements.map { $0.lowercased() }).count < plan.confirmedRequirements.count { issues.append("duplicate requirements") }
        return issues
    }

    @discardableResult
    public static func repair(_ plan: inout PromptPlan, analysis: RequestAnalysis, context: RetrievedContext? = nil) -> [String] {
        let guided = needsGuidance(analysis)
        guard guided || plan.successCriteria.contains(where: genericCriterion) else { return [] }
        let findings = guided ? issues(plan, analysis: analysis) : []
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
        if !guided { return findings }
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
        let database = has(#"\b(database|db|sql|query|queries)\b"#)
        let concurrentLoad = has(#"\b(concurren|simultaneous|multiple users|under load)\w*\b"#)
        let timeout = has(#"\btime\s?outs?\b"#)
        let motion = has(#"animat|transition|opening|closing"#)
        let security = has(#"secur|login|authentic"#)
        let ui = analysis.taskType == .ui || has(#"\bui\b|design|visual"#)
        var symptomClauses = SemanticValidator.clauses(analysis.text).filter { SemanticValidator.parse($0).isEmpty }
            .flatMap { clause in
                clause.replacingOccurrences(of: #"[,;]\s*|\s+(?:and|but)\s+"#, with: "\u{1}", options: .regularExpression)
                    .split(separator: "\u{1}").map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: " .,:;")) }
            }
            .filter { clause in
                clause.range(of: #"(?i)\b(slow|sluggish|lag|freez\w*|unresponsive|don't respond|dont respond|doesn't respond|doesnt respond|stop responding|doesn't work|doesnt work|not responding|buggy|bugs?|breaks?|breaking|fails?|failure|crashes?|intermittent|time\s?outs?|takes .*to open|switch(?:ing|es)? views?|open(?:ing)? (?:the )?(?:window|view|interface)|close(?:ing)? (?:the )?(?:window|view|interface))\b"#, options: .regularExpression) != nil
            }
        func reportsSameSymptom(_ requirement: String, _ symptom: String) -> Bool {
            PromptOptimizer.semanticallySimilar(requirement, symptom)
                || (PromptOptimizer.groundedWordCoverage(requirement, symptom) >= 0.7
                    && PromptOptimizer.groundedWordCoverage(symptom, requirement) >= 0.65)
        }
        // A symptom is observed evidence, not a desired behavior. If Qwen placed one in
        // confirmed requirements, keep it in the investigation task only.
        plan.confirmedRequirements = plan.confirmedRequirements.flatMap { item in
            if analysis.confirmedRequirements.contains(where: {
                PromptOptimizer.semanticallySimilar(item, $0)
                    || (PromptOptimizer.groundedWordCoverage(item, $0) >= 0.85
                        && PromptOptimizer.groundedWordCoverage($0, item) >= 0.85)
            }) {
                return [item]
            }
            let clauses = SemanticValidator.clauses(item)
            let retained = clauses.filter { clause in
                SemanticValidator.parse(clause).isEmpty
                    && !symptomClauses.contains { reportsSameSymptom(clause, $0) }
                    && !analysis.confirmedRequirements.contains {
                        reportsSameSymptom(item, $0) || reportsSameSymptom(clause, $0)
                    }
            }
            // Leave user-confirmed answers byte-for-byte intact when no clause needs moving.
            if retained.count == clauses.count { return [item] }
            return retained
        }
        if has(#"\bui freezes\b"#), !symptomClauses.contains(where: { $0.localizedCaseInsensitiveContains("UI freezes") }) {
            symptomClauses.append("UI freezes")
        }
        // Keep observed behavior attached to investigation work. Rephrasing symptoms as a
        // "suggested approach" blurs the difference between evidence and recommendations.
        if !symptomClauses.isEmpty {
            if let index = plan.tasks.firstIndex(where: {
                ($0.title + " " + $0.detail).range(of: #"(?i)\b(?:reproduc\w*|replay the reported|replay each reproduced)\b"#, options: .regularExpression) != nil
            }) {
                let detailWords = Lex.content(plan.tasks[index].detail)
                let missing = symptomClauses.filter { symptom in
                    Lex.coverage(Lex.content(symptom), in: detailWords) < 0.8
                }
                if !missing.isEmpty {
                    let details = missing.map { symptom in
                        symptom.replacingOccurrences(of: #"(?i)\bintermittently\s+fail(?:s|ed)?\b"#, with: "intermittent failures", options: .regularExpression)
                    }
                    let note = "The reproduction should cover: \(details.joined(separator: "; "))."
                    var detail = plan.tasks[index].detail.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let last = detail.last, !".!?".contains(last) { detail += "." }
                    plan.tasks[index].detail = [detail, note].filter { !$0.isEmpty }.joined(separator: " ")
                }
                if symptomClauses.contains(where: { $0.localizedCaseInsensitiveContains("intermittent") }) {
                    plan.tasks[index].detail = plan.tasks[index].detail.replacingOccurrences(
                        of: #"(?i)\bconsistently\s+(?:trigger|cause)\b"#, with: "may reproduce", options: .regularExpression)
                }
            } else {
                var id = "quality_reproduction"
                while plan.tasks.contains(where: { $0.id == id }) { id += "_" }
                let details = symptomClauses.map { symptom -> String in
                    if symptom.range(of: #"(?i)^intermittently fail(?:s|ed)?$"#, options: .regularExpression) != nil {
                        return database ? "Database operations fail intermittently" : "Intermittent failures"
                    }
                    if database && symptom.range(of: #"(?i)^time\s?out\b"#, options: .regularExpression) != nil {
                        return "Database operations \(symptom)"
                    }
                    return symptom
                }
                plan.tasks.insert(PlanTask(id: id, title: "Reproduce the reported symptoms",
                                           detail: "Repeat the affected operation under the reported conditions and record which symptoms occur: \(details.joined(separator: "; "))."), at: 0)
            }
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
        let remedy = #"(?i)^(?:add|integrate|introduce|enforce|replace|enable|implement|encrypt|update|upgrade|adopt|migrate|use|configure|cache|index|rebuild|reindex|create|install|switch|parallelize|batch|adjust|tune|optimi[sz]e|regularly)\b"#
        func prescribes(_ text: String) -> Bool {
            guard text.range(of: remedy, options: .regularExpression) != nil else { return false }
            // Naming an affected object ("slow queries") is not authorization for a remedy
            // ("optimize slow queries"). The user must state the action as well. Diagnostic
            // methods introduced with "use" remain investigation guidance, not a chosen fix.
            if text.range(of: #"(?i)^use\s+(?:profil(?:e|ing)|logs?|query plans?|metrics?|measurements?|tests?|traces?|the existing code|the current implementation)\b"#, options: .regularExpression) != nil {
                return false
            }
            return true
        }
        func hasUnrequestedRemedy(_ text: String) -> Bool {
            guard let regex = try? NSRegularExpression(pattern: #"(?i)\b(?:add|integrate|introduce|enforce|replace|enable|implement|encrypt|update|upgrade|adopt|migrate|configure|cache|index|rebuild|reindex|create|install|switch|parallelize|batch|adjust|tune|optimi[sz]e)\b"#) else { return false }
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            return matches.contains { match in
                guard let range = Range(match.range, in: text) else { return false }
                return !explicitlyRequested(String(text[range.lowerBound...]))
            }
        }
        func explicitlyRequested(_ text: String) -> Bool {
            var words = Lex.words(text)
            let actionVerbs: Set<String> = ["add", "integrate", "introduce", "enforce", "replace", "enable", "implement", "encrypt", "update", "upgrade", "adopt", "migrate", "use", "configure", "cache", "index", "rebuild", "reindex", "create", "install", "switch", "parallelize", "batch", "adjust", "tune", "optimize", "optimise"]
            var actions: [String] = []
            while let first = words.first, actionVerbs.contains(where: { Lex.same(first, $0) }) {
                actions.append(words.removeFirst())
            }
            guard !actions.isEmpty else { return false }
            let stop: Set<String> = ["a", "an", "the", "to", "for", "and", "with", "only", "if", "when", "in", "on", "of", "between", "from", "by", "as", "needed"]
            let target = Set(words).subtracting(stop)
            let stated = Set(Lex.words(analysis.searchText))
            let actionStated = actions.contains { action in stated.contains { Lex.same($0, action) } }
            return actionStated && !target.isEmpty && target.isSubset(of: stated)
        }
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
        } else if [.other, .ui, .performance, .bugfix, .investigation].contains(analysis.taskType),
                  (vague || analysis.taskType == .performance || analysis.taskType == .bugfix || analysis.taskType == .investigation) {
            // For diagnosis requests, remove a chosen remedy from the execution steps unless the user actually named it.
            removeTasks { !isFixStep($0.title) && prescribes($0.title) && !Lex.isObservation($0.title) && !explicitlyRequested($0.title) }
            let speculative = plan.suggestedDecisions.filter { prescribes($0) && !Lex.isHedged($0) && !explicitlyRequested($0) }
            candidates += speculative
            plan.suggestedDecisions.removeAll { speculative.contains($0) }
        }
        for index in plan.tasks.indices {
            if isFixStep(plan.tasks[index].title), prescribes(plan.tasks[index].detail), !explicitlyRequested(plan.tasks[index].detail) {
                plan.tasks[index].detail = "Make a focused change supported by the diagnostic evidence."
            } else if Lex.isObservation(plan.tasks[index].title), hasUnrequestedRemedy(plan.tasks[index].detail) {
                plan.tasks[index].detail = "Inspect the current behavior and gather evidence; treat changes as candidates until the cause is confirmed."
            } else if plan.tasks[index].title.range(of: #"(?i)\bconnection\s*pool"#, options: .regularExpression) != nil {
                plan.tasks[index].detail = "Check waits, exhaustion, and configured limits under the reported workload; treat pool capacity as a candidate until metrics confirm it."
            }
        }
        plan.suggestedDecisions.removeAll { item in
            let clauses = SemanticValidator.clauses(item)
            let constraintOnly = !clauses.isEmpty && clauses.allSatisfy { !SemanticValidator.parse($0).isEmpty }
            let symptomWrapper = item.range(of: #"(?i)^\s*(?:investigate|review|address)\s+the\s+reported\s+(?:behavior|issue|symptom)\w*\s*[:—-]"#, options: .regularExpression) != nil
                && PromptOptimizer.groundedWordCoverage(item, analysis.searchText) >= 0.4
            return constraintOnly || symptomWrapper
        }
        if !candidates.isEmpty {
            var unique: [String] = []
            for candidate in candidates where !unique.contains(where: { PromptOptimizer.groundedWordCoverage($0, candidate) >= 0.5 || PromptOptimizer.groundedWordCoverage(candidate, $0) >= 0.5 }) { unique.append(candidate) }
            let genericTargets: Set<String> = ["api", "database", "configuration", "config", "monitor", "monitoring", "logging", "performance", "logic", "system", "application", "app", "functionality", "resource", "operation", "operations"]
            unique.removeAll { candidate in
                let target = candidate.replacingOccurrences(
                    of: #"(?i)^\s*(?:add|integrate|introduce|enforce|replace|enable|implement|encrypt|update|upgrade|adopt|migrate|use|configure|cache|index|rebuild|reindex|create|install|switch|parallelize|batch|adjust|tune|optimi[sz]e|regularly)\b\s*"#,
                    with: "", options: .regularExpression)
                let words = Set(Lex.content(target)).subtracting(["or", "slow", "fast", "new", "existing"])
                return !words.isEmpty && words.isSubset(of: genericTargets)
            }
            if database && concurrentLoad && timeout {
                unique.removeAll { $0.range(of: #"(?i)\bindexes?\b"#, options: .regularExpression) != nil }
                let logCoverage = (plan.tasks.map { $0.title + " " + $0.detail } + plan.verificationInstructions)
                    .contains { $0.range(of: #"(?i)\b(?:logs?|logging|monitoring)\b"#, options: .regularExpression) != nil }
                if logCoverage { unique.removeAll { $0.range(of: #"(?i)\b(?:logs?|logging|monitoring)\b"#, options: .regularExpression) != nil } }
            }
            if !unique.isEmpty {
                plan.suggestedDecisions.append("Possible causes or approaches to evaluate only if evidence supports them: " + unique.prefix(4).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .")) }.joined(separator: "; ") + ". These are hypotheses, not prescribed fixes.")
            }
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
        if performance,
           !(plan.tasks + plan.verificationInstructions.map { PlanTask(id: "", title: $0) }).contains(where: { ($0.title + " " + $0.detail).range(of: #"(?i)\b(?:profile|profiling|measure|measurement|baseline|benchmark)\w*\b"#, options: .regularExpression) != nil }) {
            var id = "quality_measure"
            while plan.tasks.contains(where: { $0.id == id }) { id += "_" }
            plan.tasks.append(PlanTask(id: id, title: "Profile the reported slow path", detail: "Measure the same workload before and after the change."))
        }
        // The user asked for a fix, so the plan must contain one even when the model only wrote investigation steps.
        if asksToFix, !plan.tasks.contains(where: { isFixStep($0.title) }) {
            let step = PlanTask(id: "quality_fix", title: "Fix confirmed issues", detail: "Make the smallest change that addresses each reproduced problem; report anything that could not be reproduced.")
            let at = plan.tasks.firstIndex { $0.title.range(of: #"(?i)\b(?:test|tests|verify|validate)\b"#, options: .regularExpression) != nil } ?? plan.tasks.endIndex
            plan.tasks.insert(step, at: at)
        }
        // Investigation comes before changes. Only tasks with no dependencies move, so a stated order is never broken.
        let investigationFirst = #"(?i)^(?:locate|find|inspect|review|map|establish|reproduce|trace|investigate)\b"#
        let early = plan.tasks.filter { $0.dependsOn.isEmpty && $0.title.range(of: investigationFirst, options: .regularExpression) != nil }
        plan.tasks = early + plan.tasks.filter { t in !early.contains { $0.id == t.id } }

        var investigations: [String] = []
        if motion {
            investigations.append("Inspect transition timing and state changes; exercise interruptions and rapid reversals. Check focus and lifecycle handling if the transition opens or closes a window.")
        }
        var observedChecks = PromptOptimizer.dedupe(symptomClauses.flatMap(observableChecks(for:)))
        if refactor { observedChecks.removeAll { $0.contains("reported failure") } }
        if database && concurrentLoad && timeout {
            // A single load comparison covers these symptoms together more clearly than
            // separate slow-operation, timeout and generic failure criteria.
            observedChecks.removeAll()
        } else if performance {
            observedChecks.removeAll { $0.localizedCaseInsensitiveContains("reported slow operation") }
        }
        let hasSpecificFailureCheck = observedChecks.contains { $0.contains("button actions") || $0.contains("interactions reported as not working") || $0.contains("froze the interface") }
        if hasSpecificFailureCheck {
            observedChecks.removeAll { $0.contains("reproduction that exposed the reported failure") }
        }
        for criterion in observedChecks {
            if plan.successCriteria.count < 6 && !plan.successCriteria.contains(where: { PromptOptimizer.semanticallySimilar($0, criterion) }) {
                plan.successCriteria.append(criterion)
            }
        }
        let reportedAPIFailure = SemanticValidator.clauses(analysis.searchText).contains { clause in
            SemanticValidator.parse(clause).isEmpty
                && clause.range(of: #"(?i)\bapi\b"#, options: .regularExpression) != nil
                && clause.range(of: #"(?i)\b(fail|error|timeout|time out|hang|crash|slow|break)\w*\b"#, options: .regularExpression) != nil
        }
        if reportedAPIFailure {
            investigations.append("Trace a failing API request through validation, handling and response generation; inspect error evidence before changing response behavior.")
        }
        if database && concurrentLoad && timeout {
            // Keep reproduction focused on symptoms. Consolidate diagnostic hypotheses in the
            // analysis task, choosing that task before a broad reproduction task that mentions DB.
            for index in plan.tasks.indices where plan.tasks[index].title.range(of: #"(?i)^reproduce\b"#, options: .regularExpression) != nil {
                let parts = plan.tasks[index].detail.components(separatedBy: ". ")
                let retained = parts.filter { part in
                    part.range(of: #"(?i)^(?:under the same load|change only measured causes|consider indexes only)\b"#, options: .regularExpression) == nil
                }
                plan.tasks[index].detail = retained.joined(separator: ". ")
            }
            func isEligibleDiagnostic(_ task: PlanTask) -> Bool {
                task.title.range(of: #"(?i)^reproduce\b|^fix\b|^test\b|^verify\b"#, options: .regularExpression) == nil
            }
            let diagnosticIndex = plan.tasks.firstIndex { isEligibleDiagnostic($0) && $0.title.range(of: #"(?i)\b(?:query|sql|profile|performance)\b"#, options: .regularExpression) != nil }
                ?? plan.tasks.firstIndex { isEligibleDiagnostic($0) && ($0.title + " " + $0.detail).range(of: #"(?i)\b(?:database|connection pool)\b"#, options: .regularExpression) != nil }
            let index = diagnosticIndex ?? plan.tasks.count
            if diagnosticIndex == nil {
                plan.tasks.append(PlanTask(id: "quality_db_diagnostics", title: "Inspect database performance", detail: ""))
            }
            let existing = (plan.tasks[index].title + " " + plan.tasks[index].detail)
            var evidence: [String] = []
            if existing.range(of: #"(?i)\bquery plans?|access patterns?\b"#, options: .regularExpression) == nil { evidence.append("query plans and access patterns") }
            if existing.range(of: #"(?i)(?:connection\s*pool|pool).{0,35}\b(?:wait|exhaustion|capacity|limit|reuse)\b|\b(?:wait|exhaustion|capacity|limit|reuse)\b.{0,35}(?:connection\s*pool|pool)"#, options: .regularExpression) == nil { evidence.append("connection-pool waits or exhaustion") }
            if existing.range(of: #"(?i)\b(lock contention|deadlock)\b"#, options: .regularExpression) == nil { evidence.append("lock contention") }
            if existing.range(of: #"(?i)\btimeout(?:s| evidence)?\b"#, options: .regularExpression) == nil { evidence.append("timeout evidence") }
            if existing.range(of: #"(?i)\b(cpu|memory|i/o|resource saturation)\b"#, options: .regularExpression) == nil { evidence.append("CPU, memory, or I/O saturation") }
            if existing.range(of: #"(?i)\bindex(?:es)?\b"#, options: .regularExpression) == nil { evidence.append("consider indexes only when query-plan evidence supports them") }
            if !evidence.isEmpty {
                let detail = "Under the reported concurrent workload, inspect \(evidence.joined(separator: ", ")) as candidate causes. Change only measured causes."
                plan.tasks[index].detail = [plan.tasks[index].detail, detail].filter { !$0.isEmpty }.joined(separator: " ")
            }
        } else if database {
            let detail = "Inspect query plans, timings and access patterns; treat bottlenecks as hypotheses until diagnostics support them."
            if let index = plan.tasks.firstIndex(where: { $0.title.range(of: #"(?i)\b(query plan|queries)\b"#, options: .regularExpression) != nil })
                ?? plan.tasks.firstIndex(where: { ($0.title + " " + $0.detail).range(of: #"(?i)\b(database|query|sql)\w*\b"#, options: .regularExpression) != nil }) {
                if !plan.tasks[index].detail.localizedCaseInsensitiveContains("query plans") {
                    plan.tasks[index].detail = [plan.tasks[index].detail, detail].filter { !$0.isEmpty }.joined(separator: " ")
                }
            } else {
                plan.tasks.append(PlanTask(id: "quality_db_diagnostics", title: "Inspect database query plans", detail: detail))
            }
        }
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
        if security { outcomes.append("Each implemented security change addresses a weakness supported by evidence and is checked against the existing sign-in policy.") }
        if ui { outcomes.append("The before-and-after comparison verifies the specific visual issues identified in the current interface without changing unrelated behavior.") }
        if analysis.taskType == .investigation { outcomes.append("Findings are supported by code or runtime evidence, and unresolved causes are labeled as unknown.") }
        for outcome in outcomes where plan.successCriteria.count < 5 && !plan.successCriteria.contains(outcome) { plan.successCriteria.append(outcome) }
        if ui && has(#"don't|dont|do not|without|keep|preserve"#) {
            plan.verificationInstructions.append("Compare the affected interface before and after to verify the user's visual constraints.")
        }
        let protectsExistingBehavior = SemanticValidator.directives(in: analysis.searchText).contains { directive in
            directive.kind == .prohibit && directive.verb == "break"
                && ["existing behavior", "existing functionality"].contains(directive.objectText.lowercased())
        }
        if protectsExistingBehavior,
           !plan.successCriteria.contains(where: { $0.range(of: #"(?i)(?:does not|doesn't|never) break (?:existing behavior|existing functionality)|preserv(?:es|e|ed) existing (?:behavior|functionality)|existing (?:behavior|functionality) remains unchanged|previously working behavior remains unchanged"#, options: .regularExpression) != nil }) {
            plan.successCriteria.append("Previously working behavior remains unchanged in the reproduced scenarios.")
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
        if performance {
            let measurement = database && concurrentLoad && timeout
                ? "Repeat the same concurrent workload before and after; record latency and timeout/failure observations without inventing a target."
                : "Measure the same representative workload before and after; report the observed result without inventing a target."
            if database && concurrentLoad && timeout {
                plan.verificationInstructions.removeAll { $0.range(of: #"(?i)\b(?:load tests?|query latency|benchmark|measure.*performance|compare.*workload)\b"#, options: .regularExpression) != nil }
                plan.verificationInstructions.removeAll { $0.range(of: #"(?i)\b(?:monitor|track|check)\b.*\b(?:database )?performance metrics\b"#, options: .regularExpression) != nil }
            }
            if !plan.verificationInstructions.contains(where: { sameGuidance($0, measurement) }) { plan.verificationInstructions.append(measurement) }
            let performanceCriterion = database && concurrentLoad && timeout
                ? "Under the same concurrent workload, the reported timeouts and intermittent failures no longer reproduce; record latency before and after."
                : "The reported slow operation shows lower measured latency on the same representative workload, with no invented numerical target."
            if !plan.successCriteria.contains(where: { sameGuidance($0, performanceCriterion) }) {
                plan.successCriteria.append(performanceCriterion)
            }
        }
        // Scenario checks use a shared sentence frame, but each named case is distinct work; only remove exact repeats.
        plan.verificationInstructions = PromptOptimizer.dedupe(plan.verificationInstructions)
        let guidanceText = (plan.guidance?.investigate ?? []) + (plan.guidance?.goodLooksLike ?? []) + (plan.guidance?.avoid ?? [])
        plan.suggestedDecisions = semanticDedupe(plan.suggestedDecisions, against: plan.tasks.map { "\($0.title) \($0.detail)" } + plan.verificationInstructions + plan.successCriteria + guidanceText)
        plan.tasks = dedupeTasks(plan.tasks)
        plan.tasks = normalizeDependencies(plan.tasks)
        return findings
    }

    private static func semanticDedupe(_ items: [String], against other: [String] = []) -> [String] {
        var kept: [String] = []
        for item in items where !(other + kept).contains(where: { sameGuidance(item, $0) }) { kept.append(item) }
        return kept
    }

    private static func dedupeTasks(_ tasks: [PlanTask]) -> [PlanTask] {
        var kept: [PlanTask] = []
        for task in tasks {
            let content = "\(task.title) \(task.detail)"
            if let index = kept.firstIndex(where: { sameGuidance(content, "\($0.title) \($0.detail)") }) {
                if task.detail.count > kept[index].detail.count { kept[index].detail = task.detail }
                kept[index].dependsOn = PromptOptimizer.dedupe(kept[index].dependsOn + task.dependsOn)
            } else { kept.append(task) }
        }
        return kept
    }

    /// Duplicate when two lines ask for the same kind of action on the same target, even if their wording differs.
    private static func sameGuidance(_ lhs: String, _ rhs: String) -> Bool {
        if PromptOptimizer.semanticallySimilar(lhs, rhs) { return true }
        func action(_ text: String) -> String {
            if text.range(of: #"(?i)\b(?:test|verify|validate|retest|assert|confirm|compare after|run (?:the )?(?:tests?|build))\b"#, options: .regularExpression) != nil { return "verify" }
            if text.range(of: #"(?i)^\s*(?:add|integrate|introduce|enforce|replace|enable|implement|encrypt|update|upgrade|adopt|migrate|use|configure|cache|index|rebuild|reindex|create|install|switch|parallelize|batch|fix|optimi[sz]e)\b|\b(?:add|introduce|implement|replace|configure|cache|rebuild|reindex)\b"#, options: .regularExpression) != nil { return "remedy" }
            if text.range(of: #"(?i)\b(?:profile|profiling|measure|measurement|benchmark|baseline|latency|timing|compare before and after)\b"#, options: .regularExpression) != nil { return "measure" }
            if text.range(of: #"(?i)\b(?:inspect|review|examine|investigate|analy[sz]e|check|monitor|trace|reproduce|identify|locate|find|audit|record|capture|collect|gather)\b"#, options: .regularExpression) != nil { return "investigate" }
            return "other"
        }
        let leftAction = action(lhs), rightAction = action(rhs)
        let diagnosticPair = ["measure", "investigate"].contains(leftAction) && ["measure", "investigate"].contains(rightAction)
        guard (leftAction == rightAction || diagnosticPair), leftAction != "other" else { return false }
        func tokens(_ text: String) -> Set<String> {
            let stop: Set<String> = ["the", "a", "an", "to", "of", "for", "and", "or", "do", "does", "not", "no", "is", "are", "be", "with", "during", "before", "after", "same", "existing", "reported", "current", "using", "from", "that", "this", "it", "only", "then"]
            var words = Set(PromptOptimizer.normalizedWords(text)).subtracting(stop)
            for word in ["profile", "profiling", "measure", "measurement", "benchmark", "baseline", "timing"] where words.contains(word) { words.insert("measure-work") }
            for word in ["query", "queries", "sql", "statement", "statements", "plan", "plans"] where words.contains(word) { words.insert("query-work") }
            for word in ["inspect", "review", "examine", "investigate", "analyze", "analyse", "check", "monitor", "trace", "measure", "profile", "reproduce", "identify", "locate", "find", "audit", "record", "capture", "collect", "gather"] where words.contains(word) { words.insert("investigate-work") }
            return words
        }
        let left = tokens(lhs), right = tokens(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        let common = left.intersection(right)
        let overlap = Double(common.count) / Double(min(left.count, right.count))
        let sameTarget = common.contains { $0.hasSuffix("-work") || ["database", "concurr", "timeout", "api", "request", "failure", "resource", "workload", "cpu", "memory", "pool", "lock"].contains($0) }
        return common.count >= 2 && overlap >= 0.55 && sameTarget
    }
}
