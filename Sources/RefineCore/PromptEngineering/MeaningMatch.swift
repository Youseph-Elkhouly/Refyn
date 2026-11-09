import Foundation

/// Checks whether a generated prompt still says what the user said, in any equivalent wording. Used by evaluations.
///
/// Wording may vary ("without altering" for "without changing", "preserve" for "keep"), but the technical meaning may not:
/// negations stay negations, and numbers, file names, identifiers and status codes must appear exactly. Unrelated words in
/// between are allowed only within a short window, so a negation in another sentence does not satisfy a constraint.
enum MeaningMatch {
    /// Words that are interchangeable for the purpose of keeping a constraint. Each group is one concept.
    static let groups: [[String]] = [
        ["change", "alter", "modify", "edit", "touch", "rewrite", "revise", "replace"],
        ["without", "not", "no", "never", "avoid", "dont", "doesnt", "shouldnt", "mustnt", "cannot", "unchanged"],
        ["keep", "preserve", "retain", "maintain", "leave", "remain", "stay"],
        ["test", "verify", "check", "validate", "exercise"],
        ["fail", "error", "break", "crash"],
    ]
    static let filler: Set<String> = ["the", "a", "an", "of", "to", "be", "is", "are", "do", "does", "should", "must", "will", "that", "it", "any", "in", "on", "for", "and", "or", "with"]

    /// Tokens whose exact form matters: numbers, status classes, file names, identifiers.
    static func isExact(_ token: String) -> Bool {
        token.contains(where: \.isNumber) || token.contains(".") || token.contains("_")
            || (token.first?.isLowercase == true && token.dropFirst().contains(where: \.isUppercase))
    }

    /// Words for the in-order comparison. Slashes and hyphens split ("async/await" is "async", "await"); dots stay inside file names and numbers.
    static func tokens(_ text: String) -> [String] {
        text.replacingOccurrences(of: "[’']", with: "", options: .regularExpression)
            .split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "." || $0 == "_") })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.filter { !$0.isEmpty }
    }

    /// Phrase pieces whose exact spelling matters: numbers, status codes, file names, paths, identifiers.
    static func exactPieces(_ phrase: String) -> [String] {
        phrase.split(whereSeparator: \.isWhitespace).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()\"'")) }
            .filter { piece in !piece.isEmpty && (piece.contains(where: \.isNumber) || piece.contains(".") || piece.contains("/") || piece.contains("_")
                                                  || (piece.first?.isLowercase == true && piece.dropFirst().contains(where: \.isUppercase))) }
    }

    static func concept(_ token: String) -> String {
        let lower = token.lowercased()
        for (i, group) in groups.enumerated() where group.contains(where: { Lex.same($0, lower) }) { return "#\(i)" }
        return Lex.stem(lower)
    }

    /// True when `text` expresses `phrase`: every exact token literally, every other word or its synonym in order within `window` words.
    static func contains(_ text: String, _ phrase: String, window: Int = 6) -> Bool {
        let want = tokens(phrase)
        guard !want.isEmpty else { return true }
        let have = tokens(text)
        // Numbers, identifiers and paths must appear as written (case aside), whatever the words around them.
        let normalized = text.replacingOccurrences(of: "[’']", with: "", options: .regularExpression)
        for piece in exactPieces(phrase) {
            guard normalized.range(of: piece, options: .caseInsensitive) != nil else { return false }
        }
        let wantConcepts = want.filter { !filler.contains($0.lowercased()) }.map { isExact($0) ? $0.lowercased() : concept($0) }
        let haveConcepts = have.map { isExact($0) ? $0.lowercased() : concept($0) }
        guard !wantConcepts.isEmpty else { return true }
        for start in haveConcepts.indices where haveConcepts[start] == wantConcepts[0] {
            var at = start
            var ok = true
            for c in wantConcepts.dropFirst() {
                guard let next = haveConcepts[(at + 1)...].prefix(window).firstIndex(of: c) else { ok = false; break }
                at = next
            }
            if ok { return true }
        }
        return false
    }
}
