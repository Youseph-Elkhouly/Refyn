import Foundation

/// Turns a validated plan into the text handed to the coding agent. Deterministic: the same plan
/// and techniques always produce the same prompt.
public enum PromptComposer {
    public struct Parts: Sendable {
        public var role: String
        public var objective: String
        public var exampleReport: String?
        public var context: RetrievedContext
    }

    public static func compose(_ plan: PromptPlan, parts: Parts) -> String {
        let t = Set(plan.selectedTechniques)
        var s: [String] = []

        if t.contains(.zeroShot) && t.isSubset(of: [.zeroShot, .contextInjection, .constraints]) {
            // Zero-shot: one clear instruction, nothing else unless constraints or context matter.
            var text = parts.objective
            if t.contains(.constraints), !plan.constraints.isEmpty { text += "\n\nConstraints: " + plan.constraints.joined(separator: " ") }
            if t.contains(.contextInjection), let ctx = contextSection(plan, parts.context, compact: true) { text += "\n\n" + ctx }
            return text
        }

        if t.contains(.role) { s.append(parts.role) }
        s.append(section("Objective", parts.objective))
        if t.contains(.contextInjection), let ctx = contextSection(plan, parts.context, compact: false) { s.append(ctx) }
        if t.contains(.structured) || t.contains(.multiStage) {
            if !plan.confirmedRequirements.isEmpty { s.append(section("Requirements (stated by the user)", bullets(plan.confirmedRequirements))) }
            if !plan.suggestedDecisions.isEmpty { s.append(section("Suggested approach (adjust if the code shows a better fit)", bullets(plan.suggestedDecisions))) }
        }
        if t.contains(.constraints), !plan.constraints.isEmpty { s.append(section("Constraints", bullets(plan.constraints))) }
        if t.contains(.toolUse) {
            s.append(section("Working method", """
            Work in short act–observe cycles: search and read the relevant code before editing, make one focused change, \
            run the relevant command, read its output, then decide the next step. Base each step on what you observed, not on assumptions.
            """))
        }
        if t.contains(.decomposition), !plan.tasks.isEmpty, !t.contains(.promptChaining) {
            s.append(section(t.contains(.multiStage) ? "Stage 2 — Implement" : "Tasks", taskList(plan.tasks, withDependencies: t.contains(.dependencyPlanning))))
        }
        if t.contains(.multiStage) {
            s.insert(section("Stage 1 — Inspect", "Read the files involved and list the ones you plan to change, with a one-line plan for each. Keep it brief and observable; no private reasoning."), at: min(s.count, insertionIndex(s)))
        }
        if t.contains(.conditionalBranching) {
            s.append(section("If things differ from expectations", bullets([
                "If the requested behavior already exists, say where and stop without changing code.",
                "If a requirement conflicts with existing code or another requirement, stop and report the conflict instead of choosing silently.",
                "If a required detail is missing, make the smallest reasonable assumption, state it, and continue.",
            ])))
        }
        if !plan.missingInformation.isEmpty { s.append(section("Open questions", bullets(plan.missingInformation.map { "\($0) — confirm in the code or ask before assuming." }))) }
        if t.contains(.verification) || t.contains(.multiStage) {
            let steps = plan.verificationInstructions.isEmpty ? ["Run the project's existing tests and build for the affected code."] : plan.verificationInstructions
            s.append(section(t.contains(.multiStage) ? "Stage 3 — Verify" : "Verification", bullets(steps)))
        }
        if t.contains(.boundedIteration) {
            s.append(section("Fix loop", """
            If verification fails: read the failure, fix the cause, and verify again. Stop after \(plan.iterationLimit) attempt\(plan.iterationLimit == 1 ? "" : "s") \
            and report what still fails and why, instead of continuing or weakening tests.
            """))
        }
        if t.contains(.selfCritique) {
            s.append(section("Before finishing", "Review your own diff against each requirement and constraint above. Fix anything missing or out of scope, and remove unrelated changes."))
        }
        if t.contains(.acceptanceCriteria), !plan.successCriteria.isEmpty { s.append(section("Acceptance criteria", checklist(plan.successCriteria))) }
        if t.contains(.outputFormat) || t.contains(.multiStage) {
            s.append(section(t.contains(.multiStage) ? "Stage 4 — Report" : "Report back", bullets([
                "Files changed, one line each on what changed.",
                "Commands and tests run, with results.",
                "Assumptions made and anything left unresolved.",
            ])))
        }
        if t.contains(.fewShot) {
            let example = parts.exampleReport?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? """
            Changed: <file> — describe the requested change
            Tests: <command> — report the actual result
            Assumptions: <only those needed to proceed>
            Unresolved: none
            """
            s.append(section("Example report", "```\n\(example)\n```"))
        }
        return s.joined(separator: "\n\n")
    }

    /// One standalone prompt per dependency level, run in order.
    public static func chain(_ plan: PromptPlan, parts: Parts) -> [String] {
        guard plan.selectedTechniques.contains(.promptChaining), let ordered = topologicalOrder(plan.tasks), ordered.count > 1 else { return [] }
        let levels = dependencyLevels(ordered)
        let groups = Dictionary(grouping: ordered, by: { levels[$0.id] ?? 0 }).sorted { $0.key < $1.key }.map(\.value)
        return groups.enumerated().map { index, tasks in
            var parts2: [String] = []
            parts2.append("Step \(index + 1) of \(groups.count) toward: \(parts.objective)")
            if index > 0 { parts2.append("The previous step is done. Re-read the code it changed before continuing.") }
            parts2.append(section("This step", taskList(tasks, withDependencies: false)))
            if !plan.constraints.isEmpty { parts2.append(section("Constraints", bullets(plan.constraints))) }
            if index == groups.count - 1 {
                if !plan.successCriteria.isEmpty { parts2.append(section("Acceptance criteria", checklist(plan.successCriteria))) }
                if !plan.verificationInstructions.isEmpty { parts2.append(section("Verification", bullets(plan.verificationInstructions))) }
            } else {
                parts2.append("Stop after this step and report the files changed and checks run.")
            }
            return parts2.joined(separator: "\n\n")
        }
    }

    public static func topologicalOrder(_ tasks: [PlanTask]) -> [PlanTask]? {
        var remaining = tasks, done = Set<String>(), out: [PlanTask] = []
        while !remaining.isEmpty {
            guard let i = remaining.firstIndex(where: { $0.dependsOn.allSatisfy(done.contains) }) else { return nil }
            let t = remaining.remove(at: i)
            out.append(t); done.insert(t.id)
        }
        return out
    }

    static func dependencyLevels(_ ordered: [PlanTask]) -> [String: Int] {
        var level: [String: Int] = [:]
        for t in ordered { level[t.id] = (t.dependsOn.compactMap { level[$0] }.max() ?? -1) + 1 }
        return level
    }

    static func contextSection(_ plan: PromptPlan, _ ctx: RetrievedContext, compact: Bool) -> String? {
        var lines: [String] = []
        if !ctx.frameworks.isEmpty { lines.append("Stack: " + ctx.frameworks.joined(separator: ", ")) }
        let refs = plan.codeReferences.prefix(compact ? 4 : 10)
        for r in refs { lines.append("`\(r.path)`\(r.symbol.map { " (\($0))" } ?? "") — \(r.reason)") }
        if refs.isEmpty { for c in ctx.components.prefix(compact ? 3 : 6) { lines.append("`\(c.path)` — \(c.type) module\(c.symbols.isEmpty ? "" : ": " + c.symbols.prefix(3).joined(separator: "; "))") } }
        if !compact { for n in ctx.notes.prefix(3) { lines.append("Project note: \(n)") } }
        guard !lines.isEmpty else { return nil }
        return section("Relevant context", bullets(lines))
    }

    static func insertionIndex(_ s: [String]) -> Int {
        // Stage 1 goes right after the objective/context/requirements, before the implementation stage.
        s.firstIndex { $0.hasPrefix("## Stage 2") || $0.hasPrefix("## Working method") } ?? s.count
    }

    static func taskList(_ tasks: [PlanTask], withDependencies: Bool) -> String {
        let ordered = topologicalOrder(tasks) ?? tasks
        let number = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0 + 1) })
        return ordered.enumerated().map { i, t in
            var line = "\(i + 1). \(t.title)"
            if !t.detail.isEmpty { line += " — \(t.detail)" }
            if withDependencies, !t.dependsOn.isEmpty { line += " (after \(t.dependsOn.compactMap { number[$0] }.map(String.init).joined(separator: ", ")))" }
            return line
        }.joined(separator: "\n")
    }

    static func section(_ title: String, _ body: String) -> String { "## \(title)\n\(body)" }
    static func bullets(_ items: [String]) -> String { items.map { "- \($0)" }.joined(separator: "\n") }
    static func checklist(_ items: [String]) -> String { items.map { "- [ ] \($0)" }.joined(separator: "\n") }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
