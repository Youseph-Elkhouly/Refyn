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
        let split = #"(?:,\s*(?:and\s+|but\s+)?|\s+but\s+|\s+and\s+|;\s*)(?="# + marker + ")"
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
        func make(_ kind: Directive.Kind, lead: String = "", verb: String = "", object: String, limit: Int? = nil, unit: String = "") -> [Directive] {
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

    /// Removes generated items that contradict, narrow or extend what the user wrote. Everything else is untouched.
    public static func correct(_ original: ModelPlan, analysis: RequestAnalysis) -> (plan: ModelPlan, notices: [String]) {
        let request = analysis.searchText
        let directives = directives(in: request)
        guard !directives.isEmpty else { return (original, []) }
        let scenarios = testScenarios(in: request)
        let trigger = failureTrigger(in: request)
        let addition = requestedAddition(in: request)
        let requestWords = Lex.words(request)

        let behaviorStems = directives.filter { $0.kind == .prohibit }.map(\.verb) + [addition].compactMap { $0.map(Lex.stem) }
            + directives.filter { $0.kind == .limit }.map { Lex.stem($0.unit) }
        let unstated = scenarios.filter { !$0.outcomeStated }
        // Words with digits ("4xx") tie an item to something the user actually specified.
        let anchors = Lex.content(request).filter { $0.contains(where: \.isNumber) }

        func violation(_ item: String, suggestion: Bool, outcome: Bool = false) -> String? {
            let words = Lex.words(item)
            let protected = Lex.hasMarker(item)
            // "Ensure 4xx is not retried and the progress UI reflects the error": a negation in one clause protects only that clause.
            let fragments = item.replacingOccurrences(of: #"\s+(?:and|but|while|so that)\s+|[,;]\s*|\.\s+"#, with: "\u{1}", options: [.regularExpression, .caseInsensitive])
                .split(separator: "\u{1}").map(String.init)
            for d in directives {
                switch d.kind {
                case .prohibit:
                    // Doing the forbidden thing to the forbidden target, with nothing saying not to.
                    for f in fragments where !Lex.hasMarker(f) {
                        let w = Lex.words(f)
                        if !d.verb.isEmpty, !d.object.isEmpty, Lex.mentions(w, d.verb), Lex.matchesObject(w, d) { return "contradicts \"\(d.clause)\"" }
                    }
                case .preserve:
                    for f in fragments where !d.object.isEmpty && !Lex.hasMarker(f) {
                        let w = Lex.words(f)
                        if Lex.changes(w, d) { return "changes something the request says to keep (\"\(d.clause)\")" }
                        // A requirement or criterion that talks about a kept thing without saying it stays as is describes new behavior for it.
                        if outcome, Lex.coverage(d.object, in: w) >= 1 { return "describes new behavior for something the request says to keep (\"\(d.clause)\")" }
                    }
                case .limit:
                    if let n = d.limit, Lex.same(Lex.stem(d.unit), "retry"), let wrong = Lex.conflictingCount(in: item, limit: n) { return "uses \(wrong) where the request limits it to \(n) \(d.unit)" }
                }
            }
            if behaviorStems.contains(where: { Lex.mentions(words, $0) }) {
                // "retry only on 5xx" turns a prohibition into a narrower rule the user never gave.
                let exclusive = words.contains { ["only", "exclusively", "solely", "just"].contains($0) }
                let novelStatus = Lex.statusClasses(in: item).filter { c in !requestWords.contains(c) }
                if exclusive, !novelStatus.isEmpty { return "narrows the behavior to \(novelStatus.joined(separator: ", ")), which the request did not say" }
                if exclusive, let trigger, !Lex.mentions(words, trigger) { return "restricts the behavior without covering \"\(trigger)\", which the request is about" }
                if !suggestion, !novelStatus.isEmpty { return "states a rule for \(novelStatus.joined(separator: ", ")) that the request did not give" }
            }
            // A scenario the user only asked to test must not get an invented expected outcome.
            if !suggestion, !protected, let scenario = unstated.first(where: { Lex.coverage(Lex.content($0.name), in: words) >= 0.99 }),
               Lex.prescribes(words), !Lex.observes(words), anchors.isEmpty || Lex.coverage(anchors, in: words) == 0 {
                return "prescribes an outcome for the \"\(scenario.name)\" case, which the request only asks to test"
            }
            return nil
        }

        var plan = original
        var removed: [String] = []
        func filter(_ items: [String], suggestion: Bool = false, outcome: Bool = false) -> [String] {
            items.filter { item in
                guard let reason = violation(item, suggestion: suggestion, outcome: outcome) else { return true }
                removed.append("\(item) (\(reason))")
                return false
            }
        }
        if violation(plan.objective, suggestion: false) != nil {
            removed.append("objective: \(plan.objective)")
            plan.objective = analysis.text.count <= 220 ? analysis.text : analysis.intent
        }
        plan.confirmedRequirements = filter(plan.confirmedRequirements, outcome: true)
        plan.constraints = filter(plan.constraints)
        plan.suggestedDecisions = filter(plan.suggestedDecisions, suggestion: true)
        plan.successCriteria = filter(plan.successCriteria, outcome: true)
        plan.verificationSteps = filter(plan.verificationSteps)
        var droppedTasks = Set<String>()
        for task in plan.tasks {
            if let reason = violation(task.title + " " + task.detail, suggestion: false) { droppedTasks.insert(task.id); removed.append("task \"\(task.title)\" (\(reason))") }
        }
        plan.tasks = plan.tasks.filter { !droppedTasks.contains($0.id) }.map { task in
            var t = task; t.dependsOn.removeAll { droppedTasks.contains($0) }; return t
        }
        guard !removed.isEmpty else { return (plan, []) }
        return (plan, ["Removed \(removed.count) generated item\(removed.count == 1 ? "" : "s") that conflicted with the request: " + removed.prefix(2).joined(separator: "; ") + "."])
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
                criterion = "Confirmed by a test or inspection: \(d.clause.prefix(1).lowercased() + d.clause.dropFirst())."
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
            let locating = ["locate", "find", "identify", "inspect", "read", "trace", "review", "reproduce", "investigate", "audit", "survey", "search", "check", "examine", "look"]
            if !plan.tasks.contains(where: { t in locating.contains { t.title.lowercased().hasPrefix($0) } }) {
                plan.tasks.insert(PlanTask(id: "t0", title: "Locate the code that implements this",
                                           detail: "No file has been confirmed as relevant; find the real implementation before changing anything."), at: 0)
            }
        }

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
    static let changeVerbs = ["change", "modify", "alter", "touch", "break", "rename", "edit", "rewrite", "redesign", "replace", "restructure", "move"]
    static let introduceVerbs = ["add", "introduce", "display", "show", "update", "change", "modify", "alter", "redesign", "replace", "rename", "remove", "expose", "extend",
                                  "surface", "render", "rewrite", "adjust", "indicate", "create", "insert", "include", "swap", "reorder", "reflect", "track", "animate", "highlight", "increment", "count"]
    static let visibleThings = ["display", "show", "banner", "toast", "counter", "badge", "label", "indicator", "message", "spinner", "text", "animation", "alert", "notify", "notification", "popup"]
    static let interfaceWords = ["ui", "ux", "interface", "screen", "layout", "view", "design", "indicator", "progress", "display", "style", "theme", "bar", "component"]
    static let apiWords = ["api", "signature", "endpoint", "contract", "protocol", "interface"]
    static let prescribingWords = ["retry", "retried", "succeed", "fail", "queue", "show", "display", "return", "throw", "block", "disable", "automatically", "resume", "abort", "cancel", "should", "must", "always", "never", "handled", "handle", "correctly", "gracefully", "recover", "recovers"]
    static let observingWords = ["observe", "report", "record", "document", "verify", "test", "exercise", "run", "cover", "inspect", "check", "measure", "assert", "determine"]

    static func words(_ s: String) -> [String] {
        s.lowercased().replacingOccurrences(of: "[’']", with: "", options: .regularExpression)
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
        if x == y { return true }
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

    static func prescribes(_ words: [String]) -> Bool { prescribingWords.contains { mentions(words, $0) } }
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
        if has(#"\blatency\b|\bthroughput\b|\bfaster\b|\bspeed up\b"#) {
            out.append("Latency is the time one operation takes; throughput is how many complete per unit of time. Say which one is being improved and measure it before and after.")
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
