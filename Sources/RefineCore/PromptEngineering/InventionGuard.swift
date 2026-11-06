import Foundation

/// Removes unsupported specifics before generated plan text can become part of the final prompt.
/// A detail is supported only by the request, user answers, or bounded retrieved workspace context.
public enum InventionGuard {
    public struct Result: Sendable {
        public var plan: ModelPlan
        public var demoted: [String]
        public var unverified: [String]
        public var notices: [String] {
            guard hasViolations else { return [] }
            var messages: [String] = []
            if !demoted.isEmpty {
                messages.append("Removed unsupported specifics from generated instructions and moved them to optional suggestions: \(demoted.prefix(2).joined(separator: "; "))")
            }
            if !unverified.isEmpty { messages.append("Unsupported specifics were removed: \(unverified.prefix(5).joined(separator: ", ")).") }
            return messages
        }
        public var hasViolations: Bool { !demoted.isEmpty || !unverified.isEmpty }
    }

    static let ignored: Set<String> = ["e.g", "i.e", "etc", "vs", "a.k.a"]

    public static func apply(to original: ModelPlan, analysis: RequestAnalysis, context: RetrievedContext, allowedNumbers: Set<Int> = []) -> Result {
        let sources = sources(analysis: analysis, context: context).joined(separator: "\n")
        func unsupported(_ text: String) -> [String] {
            unsupportedSpecifics(in: text, sources: sources, allowedNumbers: allowedNumbers)
        }

        var plan = original
        var demoted: [String] = []
        var unverified: [String] = []

        // Keep the objective anchored to the user's request. If a generated rewrite adds a
        // concrete detail, use the original wording and save the generated variant as optional.
        if !unsupported(plan.objective).isEmpty {
            demoted.append(plan.objective)
            unverified += unsupported(plan.objective)
            plan.objective = analysis.intent
        }
        if !unsupported(plan.role).isEmpty {
            unverified += unsupported(plan.role)
            plan.role = ""
        }
        if let report = plan.exampleReport, !unsupported(report).isEmpty {
            unverified += unsupported(report)
            plan.exampleReport = nil
        }

        func keepOrDemote(_ values: [String]) -> [String] {
            values.filter { value in
                let terms = unsupported(value)
                guard !terms.isEmpty else { return true }
                demoted.append(value)
                unverified += terms
                return false
            }
        }
        plan.confirmedRequirements = keepOrDemote(plan.confirmedRequirements)
        plan.constraints = keepOrDemote(plan.constraints)
        plan.missingInformation = keepOrDemote(plan.missingInformation)

        // Optional suggestions may contain new ideas, but unsupported concrete details must be
        // visible as suggestions and flagged so the single corrective attempt can remove them.
        for suggestion in plan.suggestedDecisions { unverified += unsupported(suggestion) }

        var references: [ModelPlan.Reference] = []
        for reference in plan.codeReferences {
            // Paths were already checked against `knownPaths` by ModelPlan.validated. Check only
            // model-supplied symbols and explanations here so a valid parent path stays intact.
            let text = [reference.symbol ?? "", reference.reason].joined(separator: " ")
            let terms = unsupported(text)
            if terms.isEmpty { references.append(reference) }
            else { unverified += terms }
        }
        plan.codeReferences = references

        // Unsupported task details are not allowed to survive merely as executable instructions.
        // Move those tasks to suggestions and remove downstream tasks that depend on them.
        let unsupportedTaskIDs = Set(plan.tasks.filter { task in
            let terms = unsupported(task.title + " " + task.detail)
            guard !terms.isEmpty else { return false }
            demoted.append(([task.title, task.detail].filter { !$0.isEmpty }).joined(separator: " — "))
            unverified += terms
            return true
        }.map(\.id))
        var removedIDs = unsupportedTaskIDs
        var changed = true
        while changed {
            changed = false
            for task in plan.tasks where !removedIDs.contains(task.id) && !Set(task.dependsOn).isDisjoint(with: removedIDs) {
                removedIDs.insert(task.id)
                demoted.append(([task.title, task.detail].filter { !$0.isEmpty }).joined(separator: " — "))
                changed = true
            }
        }
        plan.tasks.removeAll { removedIDs.contains($0.id) }

        plan.successCriteria = keepOrDemote(plan.successCriteria)
        plan.verificationSteps = keepOrDemote(plan.verificationSteps)

        let uniqueDemoted = unique(demoted)
        plan.suggestedDecisions += uniqueDemoted.filter { item in
            !plan.suggestedDecisions.contains { $0.caseInsensitiveCompare(item) == .orderedSame }
        }
        return Result(plan: plan, demoted: uniqueDemoted, unverified: unique(unverified))
    }

    static func sources(analysis: RequestAnalysis, context: RetrievedContext) -> [String] {
        var out = [analysis.searchText, context.workspaceName] + context.languages + context.frameworks + context.notes
        for component in context.components {
            out += [component.name, component.path] + component.files + component.symbols + component.routes
        }
        return out
    }

    static func unsupportedSpecifics(in text: String, sources: String, allowedNumbers: Set<Int>) -> [String] {
        let allTerms = RequestAnalysis.keyTerms(text)
        let terms = allTerms.filter { term in
            !allTerms.contains { other in other != term && other.localizedCaseInsensitiveContains(term) }
        }
        return terms.filter { term in
            let lower = term.lowercased()
            if ignored.contains(lower) || isSupported(term, in: sources) { return false }
            if let number = Int(term), allowedNumbers.contains(number) { return false }
            // Dependency ordinals such as "after 1" describe the plan structure, not the task.
            if Int(term) != nil, text.range(of: #"\bafter\s+\#(term)\b"#, options: .caseInsensitive) != nil { return false }
            // A numeric task-list prefix is formatting, not a claimed requirement.
            if Int(term) != nil, text.split(separator: "\n").contains(where: { line in
                String(line).range(of: #"^\s*\#(term)[.)]\s"#, options: [.regularExpression, .caseInsensitive]) != nil
            }) { return false }
            return true
        }
    }

    private static func isSupported(_ term: String, in sources: String) -> Bool {
        if term.contains("/") { return sources.localizedCaseInsensitiveContains(term) }
        // Exact-ish token boundaries avoid treating "12" as support for "2" while allowing
        // punctuation around paths, names, and quoted strings.
        let escaped = NSRegularExpression.escapedPattern(for: term)
        let pattern = "(?i)(?<![A-Za-z0-9_])\(escaped)(?![A-Za-z0-9_])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return sources.localizedCaseInsensitiveContains(term)
        }
        let found = regex.firstMatch(in: sources, range: NSRange(sources.startIndex..., in: sources)) != nil
        return found
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }
}
