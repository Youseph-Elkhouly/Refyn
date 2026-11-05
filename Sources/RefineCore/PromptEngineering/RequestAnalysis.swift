import Foundation

/// Deterministic first pass over a rough request: intent, task type, stated constraints and the terms
/// that must survive optimization. Runs locally and never calls a model.
public struct RequestAnalysis: Sendable, Hashable {
    public var text: String
    public var intent: String
    public var taskType: TaskType
    public var constraints: [String]
    public var keyTerms: [String]
    public var complexity: Int
    public var mentionsTests: Bool
    public var hasConditions: Bool
    /// Most important unanswered task-specific details. Always available without an LLM.
    public var gaps: [RequirementGap] { RequirementChecklist.gaps(for: self) }

    public func gaps(context: RetrievedContext?) -> [RequirementGap] { RequirementChecklist.gaps(for: self, context: context) }

    public init(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = text
        let sentences = Self.sentences(text)
        intent = sentences.first.map { Self.stripFiller($0) } ?? text
        taskType = Self.classify(text)
        // A sentence containing one constraint can still be the entire multi-part request.
        // Keep the extracted constraint list focused; the full request is preserved separately.
        constraints = Array(Set(sentences.filter(Self.isConstraint).map { Self.stripFiller($0) }
            .filter { !$0.isEmpty && $0.count <= 120 })).sorted()
        keyTerms = Self.keyTerms(text)
        let lower = text.lowercased()
        mentionsTests = ["test", "spec", "coverage", "ci"].contains { lower.contains($0) }
        hasConditions = [" if ", " unless ", " when ", " otherwise ", "in case"].contains { " \(lower) ".contains($0) }
        let words = text.split(whereSeparator: \.isWhitespace).count
        let clauses = sentences.count + text.components(separatedBy: " and ").count - 1 + text.components(separatedBy: "\n").count - 1
        complexity = min(10, words / 15 + clauses / 2 + (hasConditions ? 1 : 0) + (mentionsTests ? 1 : 0) + keyTerms.count / 3
                         + ([.feature, .refactor, .performance].contains(taskType) ? 1 : 0))
    }

    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .localized]) { s, _, _, _ in
            if let s { out.append(contentsOf: s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }) }
        }
        return out.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-*• ")) }.filter { !$0.isEmpty }
    }

    static let fillers = ["um", "uh", "erm", "like,", "you know,", "basically,", "so basically", "i mean,", "kind of", "sort of", "please", "can you", "could you", "i want you to", "i need you to", "i'd like you to"]

    static func stripFiller(_ s: String) -> String {
        var out = s
        for f in fillers {
            out = out.replacingOccurrences(of: "\\b\(NSRegularExpression.escapedPattern(for: f))\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        }
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.prefix(1).uppercased() + out.dropFirst()
    }

    static func isConstraint(_ s: String) -> Bool {
        let l = " " + s.lowercased() + " "
        return [" don't ", " do not ", " dont ", " must ", " never ", " without ", " keep ", " only ", " avoid ", " preserve ", " shouldn't ", " should not ", " no new ", " backwards compatible", " don’t "].contains { l.contains($0) }
    }

    static func classify(_ text: String) -> TaskType {
        let l = text.lowercased()
        // A request is a testing task only when tests are what it leads with; "…and add tests" is part of a feature.
        let opening = l.split(whereSeparator: \.isWhitespace).prefix(4).joined(separator: " ")
        if ["write tests", "add tests", "unit test", "test coverage", "integration test", "increase coverage"].contains(where: opening.contains) { return .test }
        let rules: [(TaskType, [String])] = [
            (.bugfix, ["fix", "bug", "broken", "crash", "error", "fails", "failing", "regression", "doesn't work", "not working", "issue"]),
            (.performance, ["slow", "performance", "optimize", "speed up", "latency", "memory usage", "faster"]),
            (.refactor, ["refactor", "clean up", "cleanup", "restructure", "rename", "extract", "simplify", "reorganize", "migrate"]),
            (.ui, ["ui", "button", "layout", "css", "style", "screen", "view", "modal", "design", "animation", "dark mode"]),
            (.docs, ["document", "readme", "docs", "comment"]),
            (.config, ["config", "env", "deploy", "ci ", "pipeline", "docker", "dependency", "upgrade"]),
            (.investigation, ["why", "investigate", "explain", "figure out", "find out", "how does"]),
            (.feature, ["add", "implement", "build", "create", "support", "new", "integrate", "allow"]),
        ]
        for (type, words) in rules where words.contains(where: { l.contains($0) }) { return type }
        return .other
    }

    /// Identifiers, file paths, quoted strings and numbers — the specifics a rewrite must not lose.
    static func keyTerms(_ text: String) -> [String] {
        var terms: [String] = []
        let patterns = [
            "`([^`]+)`", "\"([^\"]{2,60})\"", "'([^'\\s]{2,60})'",
            "\\b([\\w./-]+\\.[a-zA-Z]{1,5})\\b",                 // file names
            "\\b([a-z]+[A-Z][A-Za-z0-9]*)\\b",                 // camelCase
            "\\b([A-Z][a-z0-9]+[A-Z][A-Za-z0-9]*)\\b",         // PascalCase with an inner capital
            "\\b([a-z0-9]+_[a-z0-9_]+)\\b",                    // snake_case
            "(/[\\w/:{}\\[\\]-]+)",                           // routes / paths
            "\\b(\\d+(?:\\.\\d+)?(?:ms|s|px|%|mb|gb|kb)?)\\b",   // numbers and units
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r = Range(m.range(at: 1), in: text) { terms.append(String(text[r])) }
            }
        }
        var seen = Set<String>()
        return terms.filter { $0.count > 1 && seen.insert($0.lowercased()).inserted }
    }

    /// Terms from the original request that are absent from `prompt`.
    public func missingTerms(in prompt: String) -> [String] {
        let l = prompt.lowercased()
        return keyTerms.filter { !l.contains($0.lowercased()) }
    }
}

/// Removes filler from dictated text without changing technical terms.
public enum TranscriptCleaner {
    public static func clean(_ transcript: String) -> String {
        var out = transcript
        let fillers = ["\\bum+\\b,?", "\\buh+\\b,?", "\\berm\\b,?", "\\bhmm+\\b,?", "\\byou know,?\\s", "\\bi mean,\\s", "\\blike,\\s", "\\bbasically,?\\s", "\\bsort of\\s", "\\bkind of\\s"]
        for f in fillers { out = out.replacingOccurrences(of: f, with: "", options: [.regularExpression, .caseInsensitive]) }
        // Stuttered repeats: "the the" → "the".
        out = out.replacingOccurrences(of: "\\b(\\w+)(\\s+\\1\\b)+", with: "$1", options: [.regularExpression, .caseInsensitive])
        out = out.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\s+([,.?!])", with: "$1", options: .regularExpression)
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = out.first else { return out }
        return first.uppercased() + out.dropFirst()
    }
}
