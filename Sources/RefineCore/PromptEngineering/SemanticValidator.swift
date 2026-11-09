import Foundation

/// Checks a generated plan against what the user actually said, using only the request text. It never calls a model.
///
/// The request is read as a list of directives: prohibitions ("don't retry 4xx"), things to keep unchanged ("keep the
/// current progress UI", "don't change the upload API"), limits ("max 2 retries") and scenarios to test. A generated
/// item that contradicts, narrows or silently extends a directive is removed, and a directive the plan left out is
/// restored. Only the affected items change; the rest of the plan is kept.
public enum SemanticValidator {
    // MARK: Directives

    public struct Directive: Equatable, Sendable {
        public enum Kind: Sendable { case prohibit, preserve, limit }
        public var kind: Kind
        /// The clause as the user wrote it, trimmed.
        public var clause: String
        /// What is forbidden ("retry"). Empty for preserve and limit clauses.
        public var verb: String
        /// Content words of what the clause is about ("4xx", "responses").
        public var object: [String]
        public var objectText: String
        public var limit: Int?
        public var unit: String

        var core: [String] { (verb.isEmpty ? [] : [verb]) + object }
    }

    /// Splits a request into clauses at the points where a new instruction begins ("…, max 2 retries, and test …").
    static func clauses(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "’", with: "'")
        let marker = #"(?:don'?t|do not|never|keep|max(?:imum)?\b|at most|up to|no more than|without|must|avoid|preserve|leave|only|no\s|test|ensure|make sure|add|implement|create|build|write|run|fix|update|make|refactor|use|support|handle|include|report|then)"#
        let split = #"(?:,\s*(?:and\s+|but\s+)?|\s+but\s+|\s+and\s+|;\s*|\s+(?=without\b))(?="# + marker + ")"
        var out: [String] = []
        // Dictated or hurried requests often have no capitals after a full stop, so split on punctuation rather than language rules.
        let sentences = normalized.components(separatedBy: .newlines).flatMap {
            $0.replacingOccurrences(of: #"(?<=[.!?])\s+"#, with: "\u{2}", options: .regularExpression).split(separator: "\u{2}").map(String.init)
        }.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-*• ").union(.whitespaces)) }.filter { !$0.isEmpty }
        for sentence in sentences {
            let marked = sentence.replacingOccurrences(of: split, with: "\u{1}", options: [.regularExpression, .caseInsensitive])
            out += marked.split(separator: "\u{1}").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!").union(.whitespacesAndNewlines)) }
        }
        return out.filter { !$0.isEmpty }
    }

    /// One clause can forbid or preserve several things ("don't change the result order or the public API"). Each gets its own directive.
    static func parse(_ clause: String) -> [Directive] {
        let text = clause.replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: .whitespacesAndNewlines)
        func make(_ kind: Directive.Kind, lead: String = "", verb: String = "", object rawObject: String, limit: Int? = nil, unit: String = "") -> [Directive] {
            // "mess up the design" keeps "the design"; "without breaking anything" protects existing behavior as a whole.
            var object = rawObject.replacingOccurrences(of: #"(?i)^up\s+"#, with: "", options: .regularExpression)
            if kind == .preserve, ["anything", "everything", "stuff", "things"].contains(object.lowercased().trimmingCharacters(in: .whitespaces)) { object = "existing behavior" }
            let parts = kind == .limit ? [object]
                : object.replacingOccurrences(of: #"\s*,\s*(?:and\s+|or\s+)?|\s+(?:and|or)\s+"#, with: "\u{1}", options: [.regularExpression, .caseInsensitive])
                    .split(separator: "\u{1}").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard parts.count > 1 else {
                return [Directive(kind: kind, clause: text, verb: Lex.stem(verb), object: Lex.content(object), objectText: object, limit: limit, unit: unit)]
            }
            return parts.map { part in
                Directive(kind: kind, clause: "\(lead) \(part)".trimmingCharacters(in: .whitespaces), verb: Lex.stem(verb), object: Lex.content(part), objectText: part, limit: limit, unit: unit)
            }
        }
        func isChange(_ verb: String) -> Bool { Lex.changeVerbs.contains { Lex.same($0, verb) } }
        if let m = text.captures(#"^(?:don'?t|do not)\s+mess up\s+(.+)$"#) {
            return make(.preserve, object: m[1])
        }
        if let m = text.captures(#"^((?:please\s+)?(?:don'?t|do not|never|avoid|must not|should not|shouldn'?t))\s+(\w+)\s*(.*)$"#) {
            return isChange(m[2]) ? make(.preserve, lead: "\(m[1]) \(m[2])", object: m[3]) : make(.prohibit, lead: "\(m[1]) \(m[2])", verb: m[2], object: m[3])
        }
        if let m = text.captures(#"^(without)\s+(\w+)\s*(.*)$"#) {
            return isChange(m[2]) ? make(.preserve, lead: "\(m[1]) \(m[2])", object: m[3]) : make(.prohibit, lead: "\(m[1]) \(m[2])", verb: m[2], object: m[3])
        }
        if let m = text.captures(#"^(keep|preserve|leave|maintain|retain)\s+(.*?)(?:\s+(?:unchanged|as is|the same))?$"#), !m[2].isEmpty {
            return make(.preserve, lead: m[1], object: m[2])
        }
        if let m = text.captures(#"^(?:max(?:imum)?(?:\s+of)?|at most|up to|no more than|limited to)\s+(\d+)\s+(\w+)"#), let n = Int(m[1]) {
            return make(.limit, object: m[2], limit: n, unit: m[2])
        }
        return []
    }

    public static func directives(in text: String) -> [Directive] { clauses(text).flatMap(parse) }

    // MARK: Request facts

    /// What the user wants to test, and whether the request says what the outcome should be.
    struct Scenario: Equatable { var name: String; var outcomeStated: Bool }

    static func testScenarios(in text: String) -> [Scenario] {
        let all = clauses(text)
        for clause in all {
            guard let m = clause.captures(#"^tests?\s+(?:the\s+)?(.+)$"#) else { continue }
            var list = m[1]
            for suffix in [" cases", " case", " scenarios", " scenario"] where list.lowercased().hasSuffix(suffix) {
                list = String(list.dropLast(suffix.count)); break
            }
            let names = list.replacingOccurrences(of: #"\s*,\s*(?:and\s+|or\s+)?|\s+(?:and|or)\s+"#, with: "\u{1}", options: [.regularExpression, .caseInsensitive])
                .split(separator: "\u{1}").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard (1...6).contains(names.count), names.allSatisfy({ $0.split(separator: " ").count <= 4 }),
                  !names.contains(where: { ["that", "it", "if", "whether", "everything", "all"].contains($0.lowercased().split(separator: " ").first.map(String.init) ?? "") }) else { continue }
            let others = all.filter { $0 != clause }.joined(separator: " ")
            return names.map { name in Scenario(name: name, outcomeStated: Lex.coverage(Lex.content(name), in: Lex.content(others)) >= 0.5) }
        }
        return []
    }

    /// "fail on timeout" → "timeout": the condition the user wants handled.
    static func failureTrigger(in text: String) -> String? {
        text.captures(#"(?i)\b(?:fail|fails|failing|failed|errors?|crash(?:es)?|breaks?)\s+(?:on|with|due to|from|when|after|during)\s+(?:a\s+|an\s+|the\s+)?(\w+)"#)?[1]
    }

    /// "add retry" → "retry": the thing the user asked to introduce.
    static func requestedAddition(in text: String) -> String? {
        text.captures(#"(?i)\b(?:add|implement|introduce|support|build)\s+(?:a\s+|an\s+|the\s+|some\s+)?(\w+)"#)?[1]
    }

    // MARK: Correction of a generated plan

    /// One change the validator made, with the reason. Used for notices, the pipeline trace and evaluation.
    public struct Correction: Equatable, Sendable {
        public enum Action: String, Sendable { case removed, demoted, rewritten }
        public var list: String
        public var original: String
        /// The clause that was removed, moved or rewritten.
        public var clause: String
        public var action: Action
        public var reason: String
    }

    enum ListKind: String { case objective, requirement, constraint, suggestion, criterion, verification, task
        var isOutcome: Bool { self == .requirement || self == .criterion || self == .constraint }
    }

    struct Finding { enum Severity { case delete, demote, rewrite(String) }; var severity: Severity; var reason: String }

    /// Corrects generated text clause by clause. A clause that contradicts or extends the request is removed or rewritten;
    /// the rest of the item survives. When a clause is only unsupported rather than contradictory, it is demoted to a suggestion.
    public static func correct(_ original: ModelPlan, analysis: RequestAnalysis, context: RetrievedContext? = nil) -> (plan: ModelPlan, notices: [String]) {
        let (plan, corrections) = correctWithReport(original, analysis: analysis, context: context)
        return (plan, notice(for: corrections).map { [$0] } ?? [])
    }

    public static func notice(for corrections: [Correction]) -> String? {
        guard !corrections.isEmpty else { return nil }
        let summary = corrections.prefix(2).map { "\($0.action.rawValue) \"\($0.clause)\" (\($0.reason))" }.joined(separator: "; ")
        return "Corrected \(corrections.count) clause\(corrections.count == 1 ? "" : "s") that conflicted with the request: \(summary)."
    }

    public static func correctWithReport(_ original: ModelPlan, analysis: RequestAnalysis, context: RetrievedContext? = nil) -> (plan: ModelPlan, corrections: [Correction]) {
        let request = analysis.searchText
        let directives = directives(in: request)
        let scenarios = testScenarios(in: request)
        let trigger = failureTrigger(in: request)
        let addition = requestedAddition(in: request)
        let requestWords = Lex.words(request)
        let supportedTech = Set(RequestAnalysis.technologies(in: ([request] + InventionGuard.sources(analysis: analysis, context: context ?? RetrievedContext(workspaceName: "", languages: [], frameworks: [], components: [], notes: [], analyzed: false))).joined(separator: "\n")).map { $0.lowercased() })
        let behaviorStems = directives.filter { $0.kind == .prohibit }.map(\.verb) + [addition].compactMap { $0.map(Lex.stem) }
            + directives.filter { $0.kind == .limit }.map { Lex.stem($0.unit) }
        let unstated = scenarios.filter { !$0.outcomeStated }
        // Words with digits ("4xx") tie a clause to something the user actually specified.
        let anchors = Lex.content(request).filter { $0.contains(where: \.isNumber) }
        // Words that signal new behavior for a thing the user said to keep as it is.
        let addedBehavior: Set<String> = Set(([addition].compactMap { $0 } + [trigger].compactMap { $0 } + directives.filter { $0.kind == .limit }.map(\.unit)
            + ["error", "retry", "attempt", "state", "counter", "count", "message", "indicator", "spinner", "status"]).map(Lex.stem))

        func check(_ clause: String, kind: ListKind) -> Finding? {
            let words = Lex.words(clause)
            let marked = Lex.hasMarker(clause)
            let observing = Lex.isObservation(clause)
            let hedged = Lex.isHedged(clause)
            for d in directives {
                switch d.kind {
                case .prohibit:
                    // The forbidden action on the forbidden target with nothing in the clause saying not to. Any role: even a test
                    // must not assert that the forbidden thing happens.
                    if !marked, !d.verb.isEmpty, !d.object.isEmpty, Lex.mentions(words, d.verb), Lex.matchesObject(words, d) {
                        return Finding(severity: .delete, reason: "contradicts \"\(d.clause)\"")
                    }
                case .preserve:
                    guard !marked, !d.object.isEmpty else { break }
                    // Testing or reading a kept thing is fine; acting on it is not. The verb must come before what it acts on.
                    if !observing, Lex.changesStructurally(words, d) { return Finding(severity: .delete, reason: "changes something the request says to keep (\"\(d.clause)\")") }
                    // The kept thing must be the one receiving the new behavior ("Progress UI reflects retry status"), not merely used by it
                    // ("CSV export is available with filters applied").
                    if kind.isOutcome, Lex.coverage(d.object, in: words) >= 1,
                       let objectAt = d.object.compactMap({ o in words.firstIndex(where: { Lex.same($0, o) }) }).min(),
                       let addedAt = words.indices.first(where: { i in addedBehavior.contains { Lex.same($0, words[i]) } && !d.object.contains { Lex.same($0, words[i]) } }),
                       objectAt < addedAt {
                        return Finding(severity: .delete, reason: "describes new behavior for something the request says to keep (\"\(d.clause)\")")
                    }
                case .limit:
                    if let n = d.limit, Lex.same(Lex.stem(d.unit), "retry"), let wrong = Lex.conflictingCount(in: clause, limit: n) {
                        let fixed = Lex.replacingConflictingCount(in: clause, limit: n, unit: d.unit)
                        return Finding(severity: .rewrite(fixed), reason: "used \(wrong) where the request limits it to \(n) \(d.unit)")
                    }
                }
            }
            if behaviorStems.contains(where: { Lex.mentions(words, $0) }), !(hedged && kind == .suggestion) {
                // "retry only on 5xx" turns a prohibition into a narrower rule the user never gave.
                let exclusive = words.contains { ["only", "exclusively", "solely", "just"].contains($0) }
                let novelStatus = Lex.statusClasses(in: clause).filter { !requestWords.contains($0) }
                if exclusive, !novelStatus.isEmpty { return Finding(severity: .delete, reason: "narrows the behavior to \(novelStatus.joined(separator: ", ")), which the request did not say") }
                if exclusive, !observing, let trigger, !Lex.mentions(words, trigger) { return Finding(severity: .delete, reason: "restricts the behavior without covering \"\(trigger)\", which the request is about") }
                // "Retries occur only on timeout and network failures": exclusivity the user never gave, with a condition they never named.
                if exclusive, kind.isOutcome, !marked, let at = words.firstIndex(where: { ["only", "exclusively", "solely", "just"].contains($0) }) {
                    let novel = words[(at + 1)...].filter { w in !Lex.stop.contains(w) && w.count > 2 && !requestWords.contains { Lex.same($0, w) } }
                    if !novel.isEmpty { return Finding(severity: .demote, reason: "adds an exclusive condition (\(novel.prefix(3).joined(separator: ", "))) that the request did not give") }
                }
                if kind.isOutcome, !novelStatus.isEmpty, !marked { return Finding(severity: .demote, reason: "states a rule for \(novelStatus.joined(separator: ", ")) that the request did not give") }
            }
            if !marked, anchors.isEmpty || Lex.coverage(anchors, in: words) == 0,
               let scenario = unstated.first(where: { Lex.coverage(Lex.content($0.name), in: words) >= 0.99 }) {
                if kind.isOutcome, Lex.prescribes(words, broad: true), !Lex.observes(words) {
                    return Finding(severity: .delete, reason: "prescribes an outcome for the \"\(scenario.name)\" case, which the request only asks to test")
                }
                // Implementing a policy for the case, or a test that asserts a specific outcome for it, is also an invented decision.
                if !kind.isOutcome {
                    let assertsOutcome = observing && Lex.assertsConcreteOutcome(clause)
                    if (!observing && Lex.prescribes(words, broad: false)) || assertsOutcome {
                        return Finding(severity: .delete, reason: "prescribes an outcome for the \"\(scenario.name)\" case, which the request only asks to test")
                    }
                }
            }
            let invented = RequestAnalysis.technologies(in: clause).filter { !supportedTech.contains($0.lowercased()) }
            if !invented.isEmpty {
                return Finding(severity: .delete, reason: "introduces \(invented.joined(separator: ", ")), which neither the request nor the workspace mentions")
            }
            return nil
        }

        var corrections: [Correction] = []
        var demoted: [String] = []

        /// Returns the item with offending clauses removed or rewritten; nil when nothing is left.
        func process(_ item: String, kind: ListKind, listName: String) -> String? {
            let pieces = Clause.split(item)
            var kept: [Clause] = []
            var changed = false
            var previousWasInventedPolicy = false
            for var piece in pieces {
                var finding = check(piece.text, kind: kind)
                // "queue and retry when the network returns": once the first half is removed, the second half is a dangling
                // part of the same invented policy.
                if finding == nil, previousWasInventedPolicy, !piece.lead.hasPrefix(". "), Lex.prescribes(Lex.words(piece.text), broad: false) {
                    finding = Finding(severity: .delete, reason: "continues a behavior the request did not ask for")
                }
                previousWasInventedPolicy = finding.map { $0.reason.hasPrefix("prescribes an outcome") || $0.reason.hasPrefix("continues") } ?? false
                guard let finding else { kept.append(piece); continue }
                changed = true
                switch finding.severity {
                case .rewrite(let text):
                    corrections.append(Correction(list: listName, original: item, clause: piece.text, action: .rewritten, reason: finding.reason))
                    piece.text = text; kept.append(piece)
                case .demote:
                    corrections.append(Correction(list: listName, original: item, clause: piece.text, action: .demoted, reason: finding.reason))
                    demoted.append(piece.text)
                case .delete:
                    corrections.append(Correction(list: listName, original: item, clause: piece.text, action: .removed, reason: finding.reason))
                }
            }
            guard changed else { return item }
            return Clause.join(kept, original: item)
        }
        func processList(_ items: [String], kind: ListKind, listName: String) -> [String] { items.compactMap { process($0, kind: kind, listName: listName) } }

        var plan = original
        if let objective = process(plan.objective, kind: .objective, listName: "objective") { plan.objective = objective }
        else { plan.objective = analysis.text.count <= 220 ? analysis.text : analysis.intent }
        plan.confirmedRequirements = processList(plan.confirmedRequirements, kind: .requirement, listName: "requirements")
        plan.constraints = processList(plan.constraints, kind: .constraint, listName: "constraints")
        plan.suggestedDecisions = processList(plan.suggestedDecisions, kind: .suggestion, listName: "suggestions")
        plan.successCriteria = processList(plan.successCriteria, kind: .criterion, listName: "criteria")
        plan.verificationSteps = processList(plan.verificationSteps, kind: .verification, listName: "verification")
        plan.suggestedDecisions += demoted.filter { d in !plan.suggestedDecisions.contains { $0.caseInsensitiveCompare(d) == .orderedSame } }

        // Tasks: correct the title and detail separately. A task disappears only when nothing valid is left in it, and
        // the tasks that depended on it inherit its own dependencies so the order stays coherent.
        var tasks: [ModelPlan.Task] = []
        var dropped: [String: [String]] = [:]
        for var task in plan.tasks {
            let title = process(task.title, kind: .task, listName: "tasks")
            let detail = task.detail.isEmpty ? "" : (process(task.detail, kind: .task, listName: "tasks") ?? "")
            switch (title, detail.isEmpty) {
            case (let t?, _): task.title = t; task.detail = detail
            case (nil, false):
                // The title was the offending part; the detail still describes valid work.
                let pieces = Clause.split(detail)
                task.title = pieces.first.map { Clause.join([$0], original: $0.text) ?? $0.text } ?? detail
                task.detail = pieces.count > 1 ? Clause.join(Array(pieces.dropFirst()), original: detail) ?? "" : ""
            default:
                dropped[task.id] = task.dependsOn
                continue
            }
            tasks.append(task)
        }
        if !dropped.isEmpty {
            func resolve(_ ids: [String], _ seen: Set<String> = []) -> [String] {
                ids.flatMap { id -> [String] in dropped[id].map { seen.contains(id) ? [] : resolve($0, seen.union([id])) } ?? [id] }
            }
            tasks = tasks.map { t in var t = t; var seen = Set<String>(); t.dependsOn = resolve(t.dependsOn).filter { $0 != t.id && seen.insert($0).inserted }; return t }
        }
        plan.tasks = tasks
        return (plan, corrections)
    }

    // MARK: Completion of the final plan

    /// Restores what the generated plan left out: every directive as a constraint and an observable criterion, the
    /// retry arithmetic, one verification step per requested scenario, and a first step to find the code.
    public static func complete(_ plan: inout PromptPlan, analysis: RequestAnalysis, definitions: Bool) {
        let request = analysis.searchText
        let directives = directives(in: request)

        func covered(_ tokens: [String], by items: [String], threshold: Double, needsMarker: Bool = false) -> Bool {
            if tokens.isEmpty { return true }
            if needsMarker { return items.contains { Lex.hasMarker($0) && Lex.coverage(tokens, in: Lex.content($0)) >= threshold } }
            return Lex.coverage(tokens, in: items.flatMap(Lex.content)) >= threshold
        }
        func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
        func tidy(_ s: String) -> String { cap(s.trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))) }

        // A prohibition, keep-unchanged clause or limit is a constraint, not a requirement. Move it, keeping any plain request ("add retry").
        var requirements: [String] = []
        for item in plan.confirmedRequirements {
            let parts = clauses(item)
            let rules = parts.filter { !parse($0).isEmpty }
            guard !rules.isEmpty else { requirements.append(item); continue }
            for rule in rules where !covered(Lex.content(rule), by: plan.constraints, threshold: 0.75) { plan.constraints.append(tidy(rule)) }
            requirements += parts.filter { parse($0).isEmpty }.map(tidy)
        }
        plan.confirmedRequirements = requirements
        // A suggestion that only restates a rule adds nothing.
        let ruleWords = (plan.constraints + plan.confirmedRequirements + plan.successCriteria).flatMap(Lex.content)
        plan.suggestedDecisions.removeAll { Lex.hasMarker($0) && Lex.coverage(Lex.content($0), in: ruleWords) >= 0.85 }

        for d in directives {
            let needsMarker = d.kind != .limit
            if !covered(d.core, by: plan.constraints + plan.confirmedRequirements, threshold: 0.75, needsMarker: needsMarker) { plan.constraints.append(tidy(d.clause)) }
            let object = d.objectText.trimmingCharacters(in: .whitespaces)
            let criterion: String
            switch d.kind {
            case .prohibit:
                criterion = "In exercised cases, the code does not \(d.verb) \(object)."
            case .preserve:
                if Lex.isInterface(d.object) {
                    criterion = "Unchanged contract: \(object) keeps its existing signature and behavior; only the internal implementation may change."
                } else if d.object.contains(where: { o in Lex.interfaceWords.contains { Lex.same($0, o) } }) {
                    criterion = "Unchanged: \(object), with no new elements, states, text or behavior added to it."
                } else {
                    criterion = "Unchanged: \(object), with nothing added, removed or altered beyond what the request names."
                }
            case .limit:
                guard let n = d.limit else { continue }
                criterion = Lex.same(Lex.stem(d.unit), "retry")
                    ? "At most \(n) retr\(n == 1 ? "y" : "ies") follow the initial attempt, so at most \(n + 1) attempts in total."
                    : "No more than \(n) \(d.unit)."
            }
            let check = d.kind == .limit ? [Lex.stem(d.unit), "total"] + d.object : d.core
            if !covered(check, by: plan.successCriteria, threshold: d.kind == .limit ? 0.99 : 0.6, needsMarker: needsMarker) { plan.successCriteria.append(criterion) }
        }

        if let trigger = failureTrigger(in: request), let addition = requestedAddition(in: request),
           !plan.successCriteria.contains(where: { Lex.mentions(Lex.words($0), trigger) && Lex.mentions(Lex.words($0), addition) }) {
            plan.successCriteria.insert("A failure caused by \(trigger) triggers the requested \(addition) behavior.", at: 0)
        }

        let scenarios = testScenarios(in: request)
        if !scenarios.isEmpty {
            // "Test timeout, offline and permanent failure cases" as a requirement repeats the verification steps written below.
            let nameTokens = scenarios.flatMap { Lex.content($0.name) }
            plan.confirmedRequirements.removeAll { r in
                let w = Lex.content(r)
                return Lex.isObservation(r) && Lex.coverage(nameTokens, in: w) >= 1 && Double(w.count) <= Double(nameTokens.count) + 3
            }
            let scenarioWords = scenarios.flatMap { Lex.content($0.name) }
            let kept = plan.verificationInstructions.filter { Lex.coverage(scenarioWords, in: Lex.content($0)) == 0 && !Lex.prescribes(Lex.words($0)) }
            var steps = scenarios.map { s -> String in
                s.outcomeStated
                    ? "Test the \(s.name) case against the behavior the request describes."
                    : "Test the \(s.name) case: run it and report the observed behavior. The request does not define the expected outcome, so do not invent one."
            }
            steps += kept.prefix(2)
            if kept.isEmpty { steps.append("Run the project's existing tests and build for the affected code.") }
            plan.verificationInstructions = steps
            // The requested cases are also an observable outcome, without inventing what each one should do.
            let names = scenarios.map(\.name)
            let nameWords = names.flatMap(Lex.content)
            if !plan.successCriteria.contains(where: { c in let w = Lex.words(c); return Lex.coverage(nameWords, in: w) >= 1 && Lex.mentions(w, "test") }) {
                let open = scenarios.filter { !$0.outcomeStated }.map(\.name)
                plan.successCriteria.append("Each requested case (\(names.joined(separator: ", "))) is exercised by a test"
                    + (open.isEmpty ? "." : "; the observed behavior of \(open.joined(separator: ", ")) is reported, not assumed."))
            }
        }

        if plan.codeReferences.isEmpty, !plan.tasks.isEmpty, [.bugfix, .feature, .performance, .refactor, .ui].contains(plan.taskType) {
            let locating = ["locate", "find", "identify", "inspect", "read", "review", "audit", "survey", "examine", "map"]
            if !plan.tasks.contains(where: { t in locating.contains { t.title.lowercased().hasPrefix($0) } }) {
                plan.tasks.insert(PlanTask(id: "t0", title: "Locate the code that implements this",
                                           detail: "No file has been confirmed as relevant; find the real implementation before changing anything."), at: 0)
            }
        }

        // A request that asks to keep something unchanged and also to add to it contradicts itself; ask instead of choosing.
        for d in directives where d.kind == .preserve && !d.object.isEmpty {
            let conflicting = clauses(request).first { c in
                parse(c).isEmpty && !Lex.isObservation(c) && Lex.changesStructurally(Lex.words(c), d)
            }
            if let c = conflicting {
                let question = "The request says \"\(d.clause)\" but also \"\(c)\". Which should take priority?"
                if !plan.missingInformation.contains(question) { plan.missingInformation.append(question) }
            }
        }

        // Details the agent can find in the repository are investigation hints, not questions for the user.
        for hint in RequirementChecklist.discoverable(for: analysis).prefix(2) where !plan.suggestedDecisions.contains(hint) { plan.suggestedDecisions.append(hint) }

        if definitions { plan.terminology = Definitions.notes(for: request).nilIfEmptyList }
    }
}

extension Array where Element == String {
    var nilIfEmptyList: [String]? { isEmpty ? nil : self }
}

// MARK: - Word-level helpers

enum Lex {
    static let stop: Set<String> = ["the", "a", "an", "of", "to", "in", "on", "for", "and", "or", "with", "current", "existing", "same", "this", "that", "any", "all",
                                     "it", "its", "be", "is", "are", "as", "not", "when", "from", "by", "at", "so", "if", "than", "then", "also", "into", "should", "must", "will", "can"]
    static let changeVerbs = ["change", "modify", "alter", "touch", "break", "rename", "edit", "rewrite", "redesign", "replace", "restructure", "move", "mess", "screw", "ruin", "wreck"]
    static let introduceVerbs = ["add", "introduce", "display", "show", "update", "change", "modify", "alter", "redesign", "replace", "rename", "remove", "expose", "extend",
                                  "surface", "render", "rewrite", "adjust", "indicate", "create", "insert", "include", "swap", "reorder", "reflect", "track", "animate", "highlight", "increment", "count"]
    static let visibleThings = ["display", "show", "banner", "toast", "counter", "badge", "label", "indicator", "message", "spinner", "text", "animation", "alert", "notify", "notification", "popup"]
    static let interfaceWords = ["ui", "ux", "interface", "screen", "layout", "view", "design", "indicator", "progress", "display", "style", "theme", "bar", "component"]
    static let apiWords = ["api", "signature", "endpoint", "contract", "protocol", "interface"]
    static let prescribingWords = ["retry", "retried", "succeed", "fail", "queue", "show", "display", "return", "throw", "block", "disable", "automatically", "resume", "abort", "cancel", "should", "must", "always", "never", "handled", "handle", "correctly", "gracefully", "recover", "recovers"]
    static let observingWords = ["observe", "report", "record", "document", "verify", "test", "exercise", "run", "cover", "inspect", "check", "measure", "assert", "determine"]

    static func words(_ s: String) -> [String] {
        s.lowercased().replacingOccurrences(of: #"\btime[sd]?\s+out\b"#, with: "timeout", options: .regularExpression)
            .replacingOccurrences(of: "[’']", with: "", options: .regularExpression)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { stem(String($0)) }
    }

    static func content(_ s: String) -> [String] { words(s).filter { $0.count >= 2 && !stop.contains($0) } }

    static func stem(_ word: String) -> String {
        var w = word.lowercased()
        if w.hasSuffix("ies"), w.count > 4 { return String(w.dropLast(3)) + "y" }
        for suffix in ["ing", "ed", "es", "s"] where w.hasSuffix(suffix) && w.count - suffix.count >= 3 {
            w = String(w.dropLast(suffix.count)); break
        }
        return w
    }

    static func same(_ a: String, _ b: String) -> Bool {
        let x = stem(a), y = stem(b)
        if x == y || x + "e" == y || y + "e" == x { return true }
        let shortest = min(x.count, y.count)
        guard shortest >= 5 else { return false }
        return zip(x, y).prefix(while: { $0 == $1 }).count >= shortest - 1
    }

    static func mentions(_ words: [String], _ term: String) -> Bool { words.contains { same($0, term) } }

    /// The share of `tokens` that appear in `corpus`.
    static func coverage(_ tokens: [String], in corpus: [String]) -> Double {
        guard !tokens.isEmpty else { return 1 }
        return Double(tokens.filter { t in corpus.contains { same($0, t) } }.count) / Double(tokens.count)
    }

    /// Whether the item talks about a prohibited target: its identifying words (anything with a digit) must be present.
    static func matchesObject(_ words: [String], _ d: SemanticValidator.Directive) -> Bool {
        let identifying = d.object.filter { $0.contains(where: \.isNumber) }
        if !identifying.isEmpty, coverage(identifying, in: words) < 1 { return false }
        return coverage(d.object, in: words) >= (identifying.isEmpty ? 0.75 : 0.5)
    }

    /// An item that adds to or alters a thing the user said to keep.
    static func changes(_ words: [String], _ d: SemanticValidator.Directive) -> Bool {
        guard introduceVerbs.contains(where: { mentions(words, $0) }) else { return false }
        if coverage(d.object, in: words) >= (d.object.count > 1 ? 0.99 : 1) { return true }
        let ui = d.object.contains { o in interfaceWords.contains { same($0, o) } }
        return ui && visibleThings.contains { mentions(words, $0) }
    }

    static func isInterface(_ object: [String]) -> Bool { object.contains { o in apiWords.contains { same($0, o) } } }

    /// Words that already say "don't", "keep" or "unchanged", so the item is not asking for the opposite.
    static func hasMarker(_ item: String) -> Bool {
        item.range(of: #"(?i)\b(?:not|never|no|without|avoid|unchanged|preserve[sd]?|keep|kept|remain[s]?|stay[s]?|still|intact|continues?|non|except|excluding|besides|skip(?:s|ping)?)\b|n['’]t\b|as before|as is|other than|rather than|instead of"#, options: .regularExpression) != nil
    }

    static let concreteOutcomeWords = ["retry", "retried", "succeed", "queue", "show", "display", "return", "throw", "block", "disable", "resume", "abort", "cancel"]
    static let vagueOutcomeWords = ["should", "must", "always", "never", "handled", "handle", "correctly", "gracefully", "recover", "recovers", "automatically"]
    static let observeLeads = ["test", "verify", "check", "assert", "validate", "confirm", "cover", "exercise", "run", "observe", "inspect", "review", "read", "examine", "trace", "reproduce",
                               "investigate", "log", "measure", "report", "document", "list", "identify", "locate", "find", "audit", "search", "compare", "determine", "simulate", "mock", "look", "understand", "map"]
    static let verbLexicon: Set<String> = Set(introduceVerbs + observeLeads + ["implement", "make", "ensure", "handle", "use", "keep", "allow", "retry", "return", "throw", "show", "log", "create", "wrap",
        "extract", "move", "convert", "replace", "apply", "define", "set", "store", "send", "fetch", "call", "build", "support", "enable", "disable", "prevent", "avoid", "treat", "classify",
        "distinguish", "differentiate", "respect", "limit", "cap", "stop", "resume", "queue", "cancel", "preserve", "maintain", "reuse", "write", "refactor", "fix", "wire", "introduce", "do", "be"])

    /// Concrete outcomes always count; vague "handled correctly" wording counts only when `broad`.
    static func prescribes(_ words: [String], broad: Bool = true) -> Bool {
        (concreteOutcomeWords + (broad ? vagueOutcomeWords : [])).contains { mentions(words, $0) }
    }

    /// A clause about testing or reading code: it observes behavior rather than implementing it.
    static func isObservation(_ clause: String) -> Bool {
        let w = words(clause).filter { !["then", "also", "first", "finally", "next", "and", "please", "now", "additionally", "plus"].contains($0) }
        guard let lead = w.first else { return false }
        if observeLeads.contains(where: { same($0, lead) }) { return true }
        let testWords = ["test", "spec", "coverage", "assertion", "scenario", "unit"]
        return ["add", "write", "create", "extend", "ensure", "make", "include", "cover"].contains(where: { same($0, lead) }) && w.dropFirst().prefix(5).contains { t in testWords.contains { same($0, t) } }
    }

    static func isHedged(_ clause: String) -> Bool {
        clause.range(of: #"(?i)\b(?:consider|optional(?:ly)?|could|may|might|perhaps|possibly|if needed|if appropriate|for example|for instance|such as|can also|you can)\b|e\.g\."#, options: .regularExpression) != nil
    }

    /// "…so that X is retried": a test clause that asserts a specific outcome.
    static func assertsConcreteOutcome(_ clause: String) -> Bool {
        guard let m = clause.captures(#"\b(?:that|to ensure|ensuring|ensure|confirm(?:ing)?|so that)\b(.*)$"#) else { return false }
        let tail = words(m[1])
        return concreteOutcomeWords.contains { mentions(tail, $0) }
    }

    /// Words that start a new relative or adverbial phrase, so a verb before them no longer acts on what comes after them.
    static let phraseBreakers: Set<String> = ["that", "which", "using", "uses", "use", "with", "while", "because", "when", "where", "by", "via", "from", "based", "respecting",
                                              "honoring", "preserving", "keeping", "retaining", "maintaining", "following", "reusing", "without", "unless", "if"]

    /// An introducing or altering verb that directly acts on the kept thing: the object follows the verb with only articles,
    /// adjectives and prepositions in between. "Create an endpoint that uses the current filters" uses them; it does not change them.
    static func changesStructurally(_ words: [String], _ d: SemanticValidator.Directive) -> Bool {
        let verbIndexes = words.indices.filter { i in introduceVerbs.contains { same($0, words[i]) } }
        guard !verbIndexes.isEmpty else { return false }
        func governed(from v: Int, to target: Int) -> Bool {
            !words[(v + 1)..<target].contains { w in phraseBreakers.contains(w) || introduceVerbs.contains { same($0, w) } }
        }
        for v in verbIndexes {
            let objectAt = d.object.compactMap { o in words.indices.first(where: { $0 > v && same(words[$0], o) }) }
            if objectAt.count == d.object.count, let first = objectAt.min(), governed(from: v, to: first) { return true }
        }
        let ui = d.object.contains { o in interfaceWords.contains { same($0, o) } }
        guard ui, coverage(d.object, in: words) >= 0.5 else { return false }
        return verbIndexes.contains { v in words.indices.contains { i in i > v && visibleThings.contains { same($0, words[i]) } && governed(from: v, to: i) } }
    }

    /// Replaces a retry or attempt count that contradicts the limit with the limit the user gave.
    static func replacingConflictingCount(in text: String, limit: Int, unit: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"(?i)\b(\d+)\s*(retries|retry|attempts?|tries|times)\b"#) else { return text }
        var out = text
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(m.range, in: out), let n = Range(m.range(at: 1), in: text).flatMap({ Int(text[$0]) }),
                  let noun = Range(m.range(at: 2), in: text).map({ text[$0].lowercased() }) else { continue }
            let isRetry = noun.hasPrefix("retr") || (noun == "times" && text.lowercased().contains("retr"))
            guard isRetry ? n != limit : (n != limit && n != limit + 1) else { continue }
            // Keep the wording the sentence used: "3 times" -> "2 times", "5 attempts" -> "3 attempts", "3 retries" -> "2 retries".
            let fixed: String
            if noun == "times" { fixed = "\(limit) times" }
            else if noun.hasPrefix("retr") { fixed = "\(limit) \(limit == 1 ? "retry" : "retries")" }
            else { fixed = "\(limit + 1) \(noun)" }
            out.replaceSubrange(whole, with: fixed)
        }
        return out
    }
    static func observes(_ words: [String]) -> Bool { observingWords.contains { mentions(words, $0) } }

    /// HTTP status classes and codes in a text, such as "5xx" or "503".
    static func statusClasses(in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"(?i)\b([1-5]xx|[1-5]\d\d)\b"#) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]).lowercased() } }
    }

    /// A retry or attempt count that does not match the limit (a limit of 2 retries allows "3 attempts" but not "3 retries").
    static func conflictingCount(in item: String, limit: Int) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"(?i)\b(\d+)\s*(retries|retry|attempts?|tries|times)\b"#) else { return nil }
        for m in re.matches(in: item, range: NSRange(item.startIndex..., in: item)) {
            guard let n = Range(m.range(at: 1), in: item).flatMap({ Int(item[$0]) }), let noun = Range(m.range(at: 2), in: item).map({ item[$0].lowercased() }) else { continue }
            let isRetry = noun.hasPrefix("retr") || (noun == "times" && item.lowercased().contains("retr"))
            if isRetry ? n != limit : (n != limit && n != limit + 1) { return "\(n) \(noun)" }
        }
        return nil
    }
}

extension String {
    /// Regex captures (index 0 is the whole match), or nil when there is no match.
    func captures(_ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: self).map { String(self[$0]) } ?? "" }
    }
}

// MARK: - Definitions

/// Short explanations of technical distinctions the request depends on. General engineering knowledge, shown only for
/// the concepts the request actually uses, and never as a stated requirement.
enum Definitions {
    static func notes(for request: String) -> [String] {
        let l = request.lowercased()
        func has(_ pattern: String) -> Bool { l.range(of: pattern, options: .regularExpression) != nil }
        var out: [String] = []
        if has(#"time[ds]? ?out|timeout"#) {
            out.append("A timeout means no response arrived before the deadline. An HTTP error response is different: the server did answer.")
        }
        if has(#"\b4xx\b|\b4\d\d\b"#) {
            out.append("HTTP 4xx means the server rejected the request as sent; repeating it unchanged normally fails again.")
        }
        if has(#"\b5xx\b|\b5\d\d\b"#) {
            out.append("HTTP 5xx means the server failed while handling the request. A later attempt may succeed.")
        }
        if has(#"\bretr(?:y|ies|ying)\b"#) {
            out.append("Transient failures (a dropped connection, a timeout) may succeed later; permanent failures cannot. Classify each failure; follow the request's own classification and do not extend it.")
        }
        if has(#"\boffline\b"#) {
            out.append("Offline means no network at all, unlike a timeout. Unless the request defines it, observe and report the behavior.")
        }
        if has(#"\bauth(?:entication|enticate|orization|orize)?\b|\blogin\b|\bsign.?in\b"#) {
            out.append("Authentication establishes who the caller is. Authorization decides what they may do. Keep them separate and change only the one the request names.")
        }
        if has(#"\blatency\b|\bthroughput\b"#) {
            out.append("Latency is the duration of one operation; throughput is the number completed per unit of time. Measure the metric named in the request.")
        }
        if has(#"\brefactor"#) {
            out.append("A refactor changes structure without changing observable behavior, so the existing tests should pass unchanged.")
        }
        if has(#"\bmigrat"#) {
            out.append("A schema migration changes structure; a data migration moves or transforms existing rows. Keep them separate and reversible.")
        }
        var seen = Set<String>()
        return Array(out.filter { seen.insert($0).inserted }.prefix(5))
    }
}


// MARK: - Clauses

/// A piece of a generated sentence, split where a new verb phrase begins, so one bad clause can be fixed without losing the rest.
struct Clause: Equatable {
    var text: String
    /// The separator that preceded it in the original ("; ", ", and ", " and ").
    var lead: String

    static func split(_ item: String) -> [Clause] {
        let text = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let re = try? NSRegularExpression(pattern: #";\s*|(?<=[.!?])\s+(?=[A-Za-z])|,\s*(?:and\s+|then\s+|but\s+)?|\s+(?:and|then|while|but|so that)\s+"#, options: [.caseInsensitive]) else { return [Clause(text: text, lead: "")] }
        var out: [Clause] = []
        var start = text.startIndex
        var lead = ""
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range, in: text) else { continue }
            let rest = text[r.upperBound...]
            let next = rest.prefix { $0.isLetter || $0.isNumber || $0 == "'" }.lowercased()
            let sentenceBreak = text[r].first.map { $0.isWhitespace } == true && r.lowerBound > text.startIndex && ".!?".contains(text[text.index(before: r.lowerBound)])
            let semicolon = text[r].hasPrefix(";")
            guard sentenceBreak || semicolon || startsVerbPhrase(next) else { continue }
            let piece = text[start..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            if !piece.isEmpty { out.append(Clause(text: piece, lead: lead)) }
            lead = String(text[r]); start = r.upperBound
        }
        let tail = text[start...].trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { out.append(Clause(text: tail, lead: lead)) }
        return out.isEmpty ? [Clause(text: text, lead: "")] : out
    }

    static func startsVerbPhrase(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        if ["also", "additionally", "plus", "finally", "next", "first"].contains(word) { return true }
        return Lex.verbLexicon.contains { Lex.same($0, word) } || (word.hasSuffix("ing") && word.count > 4)
    }

    /// Reassembles the kept clauses; nil when none remain.
    static func join(_ kept: [Clause], original: String) -> String? {
        guard !kept.isEmpty else { return nil }
        var out = ""
        for (i, c) in kept.enumerated() {
            var text = c.text.trimmingCharacters(in: CharacterSet(charactersIn: " ;,"))
            if i == 0 { if original.first?.isUppercase == true { text = text.prefix(1).uppercased() + text.dropFirst() } }
            else { out += c.lead.isEmpty ? " " : c.lead }
            out += text
        }
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("."), !out.hasSuffix(".") { out += "." }
        return out
    }
}
