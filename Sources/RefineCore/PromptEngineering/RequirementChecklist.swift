import Foundation

/// A task-specific question that can be answered from the request (or, where noted, workspace metadata).
public struct RequirementGap: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var taskType: TaskType
    public var question: String

    public init(id: String, taskType: TaskType, question: String) {
        self.id = id; self.taskType = taskType; self.question = question
    }
}

/// An answer explicitly provided by the user to a checklist question.
public struct PromptAnswer: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var question: String
    public var answer: String
    public init(id: String, question: String, answer: String) { self.id = id; self.question = question; self.answer = answer }
}

/// Deterministic checklist for catching missing requirements before a model is called.
public enum RequirementChecklist {
    private enum Detector: Sendable {
        case reproduction, expectedActual, errorEvidence
        case acceptance, scope, compatibility
        case metric, target
        case behaviorPreservation
        case testScenarios, testOutcomes
        case uiStates, platform
        case audience, documentationLocation
        case environment, rollback
        case investigationQuestion, evidence
    }

    private struct Item: Sendable {
        var id: String
        var question: String
        var detector: Detector
    }

    /// Top three unanswered items, ordered by task relevance. Easy renames and similar short
    /// non-risky edits deliberately bypass clarification to keep Auto/Basic immediate.
    public static func gaps(for analysis: RequestAnalysis, context: RetrievedContext? = nil) -> [RequirementGap] {
        if isSimpleRename(analysis.text) || (analysis.complexity < 2 && analysis.taskType == .other) { return [] }
        return Array(items(for: analysis.taskType).filter { !covered($0.detector, request: analysis.text, context: context) }
            .prefix(3).map { RequirementGap(id: $0.id, taskType: analysis.taskType, question: $0.question) })
    }

    private static func isSimpleRename(_ text: String) -> Bool {
        text.range(of: #"^\s*(rename|change|replace)\b.{1,70}\bto\b.{1,50}$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func items(for type: TaskType) -> [Item] {
        switch type {
        case .bugfix:
            [
                .init(id: "bug.reproduction", question: "What steps or conditions reproduce the bug?", detector: .reproduction),
                .init(id: "bug.expected_actual", question: "What did you expect, and what happened instead?", detector: .expectedActual),
                .init(id: "bug.error_evidence", question: "Is there an error message, log, or stack trace to include?", detector: .errorEvidence),
            ]
        case .feature:
            [
                .init(id: "feature.acceptance", question: "What observable result will tell us this feature is done?", detector: .acceptance),
                .init(id: "feature.scope", question: "What should this change include or leave untouched?", detector: .scope),
                .init(id: "feature.compatibility", question: "What existing behavior or compatibility must be preserved?", detector: .compatibility),
            ]
        case .performance:
            [
                .init(id: "performance.metric", question: "Which performance metric or operation should improve?", detector: .metric),
                .init(id: "performance.target", question: "What target or acceptable improvement should it reach?", detector: .target),
                .init(id: "performance.workload", question: "What workload or environment should be used to measure it?", detector: .environment),
            ]
        case .refactor:
            [
                .init(id: "refactor.behavior", question: "Must externally visible behavior remain exactly the same?", detector: .behaviorPreservation),
                .init(id: "refactor.scope", question: "Which callers or parts of the code are in scope?", detector: .scope),
                .init(id: "refactor.validation", question: "Which checks should confirm the refactor is safe?", detector: .testScenarios),
            ]
        case .test:
            [
                .init(id: "test.scenarios", question: "Which specific scenarios should the tests cover?", detector: .testScenarios),
                .init(id: "test.outcomes", question: "What should each scenario expect or assert?", detector: .testOutcomes),
                .init(id: "test.scope", question: "Which behavior or component should remain out of scope?", detector: .scope),
            ]
        case .ui:
            [
                .init(id: "ui.states", question: "Which empty, loading, error, or success states should the UI cover?", detector: .uiStates),
                .init(id: "ui.platform", question: "Which platform, size, or accessibility constraints matter?", detector: .platform),
                .init(id: "ui.interaction", question: "What should happen for the main user interaction?", detector: .acceptance),
            ]
        case .docs:
            [
                .init(id: "docs.audience", question: "Who is the documentation for, and what should they be able to do?", detector: .audience),
                .init(id: "docs.location", question: "Where should the documentation live?", detector: .documentationLocation),
                .init(id: "docs.examples", question: "Should it include examples or troubleshooting guidance?", detector: .acceptance),
            ]
        case .config:
            [
                .init(id: "config.environment", question: "Which environment or configuration target is involved?", detector: .environment),
                .init(id: "config.secrets", question: "Are there secret-handling or access constraints?", detector: .scope),
                .init(id: "config.rollback", question: "What rollback or recovery behavior is required?", detector: .rollback),
            ]
        case .investigation:
            [
                .init(id: "investigation.question", question: "What specific question should the investigation answer?", detector: .investigationQuestion),
                .init(id: "investigation.evidence", question: "What evidence or output should the findings include?", detector: .evidence),
            ]
        case .other:
            [
                .init(id: "other.outcome", question: "What outcome should the completed work produce?", detector: .acceptance),
                .init(id: "other.boundary", question: "What should remain unchanged?", detector: .scope),
            ]
        }
    }

    private static func covered(_ detector: Detector, request: String, context: RetrievedContext?) -> Bool {
        let text = request.lowercased()
        func contains(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        switch detector {
        case .reproduction: return contains(["when ", "after ", "before ", "steps to reproduce", "reproduces", "on launch", "on submit", "click ", "enter "])
        case .expectedActual: return (contains(["expected", "expect ", "should ", "instead of", "rather than"]) && contains(["actual", "instead", "currently", "but ", "shows ", "returns ", "happens"]))
        case .errorEvidence:
            let words = Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))
            return !words.isDisjoint(with: ["error", "exception", "stack", "trace", "log", "crash"]) || text.contains("\"") || text.contains("'")
        case .acceptance: return contains(["acceptance", "done when", "success criteria", "should ", "must ", "will ", "test ", "tests ", "works when"])
        case .scope: return contains(["only ", "scope", "in scope", "out of scope", "leave ", "without changing", "don't change", "do not change", "keep ", "preserve "])
        case .compatibility: return contains(["compatible", "compatibility", "backward", "backwards", "existing behavior", "existing api", "don't break", "do not break", "preserve ", "keep "])
        case .metric: return contains(["latency", "throughput", "memory", "cpu", "fps", "p95", "p99", "requests per", "time to", "metric"])
        case .target: return contains(["target", "under ", "below ", "less than", "at most", "no more than", "by ", "%", "ms", "seconds", "twice", "double"])
        case .behaviorPreservation: return contains(["behavior unchanged", "behaviour unchanged", "same behavior", "same behaviour", "no behavior change", "without changing behavior", "without changing behaviour", "preserve behavior", "preserve behaviour"])
        case .testScenarios: return contains(["test ", "tests ", "scenario", "case", "when ", "given "])
        case .testOutcomes: return contains(["expect", "assert", "should ", "returns ", "contains ", "equals", "fails", "passes", "expected result"])
        case .uiStates: return contains(["empty state", "loading", "error state", "success state", "empty,", "loading,", "error,", "all states"])
        case .platform:
            return contains(["macos", "ios", "android", "web", "desktop", "mobile", "accessibility", "screen reader", "keyboard", "small screen", "large screen"]) || !(context?.frameworks.isEmpty ?? true)
        case .audience: return contains(["for developers", "for users", "for admins", "audience", "beginner", "new user", "operator", "who use"])
        case .documentationLocation: return contains(["readme", "docs/", "documentation", "wiki", "guide", "reference page"])
        case .environment: return contains(["production", "staging", "development", "local", "environment", "deploy", "deployment", "workload", "traffic", "dataset"])
        case .rollback: return contains(["rollback", "roll back", "revert", "recovery", "restore"])
        case .investigationQuestion: return contains(["why ", "whether ", "which ", "where ", "how ", "find out", "determine ", "investigate whether"])
        case .evidence: return contains(["evidence", "logs", "trace", "file references", "line numbers", "reproduction", "report back", "summarize"])
        }
    }
}
