import Foundation

/// Cleans raw local-model text before it is decoded. Qwen3 can emit `<think>` blocks even when asked not to.
public enum ModelOutput {
    /// Removes reasoning blocks, including a dangling `</think>` whose opening tag was consumed by the chat template.
    public static func stripReasoning(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: [.regularExpression, .caseInsensitive])
        if let close = text.range(of: "</think>", options: [.caseInsensitive, .backwards]) {
            text = String(text[close.upperBound...])
        }
        if let open = text.range(of: "<think>", options: .caseInsensitive) {
            text = String(text[..<open.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The outermost JSON object in the output, or nil when there is none or it cannot be recovered safely.
    public static func jsonObject(from raw: String) -> String? { extract(from: raw)?.json }

    public struct Extraction: Sendable { public var json: String; public var edits: Int }
    /// More than this many inserted or dropped brackets means the output is not a small formatting slip.
    static let maxRecoveryEdits = 4

    /// Extracts the object and, for a clearly recoverable bracket slip, repairs it. Output that ends inside a string or needs
    /// more than `maxRecoveryEdits` bracket changes is rejected rather than guessed at, because the model's meaning could change.
    public static func extract(from raw: String) -> Extraction? {
        let text = stripReasoning(raw)
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return closingMissingBrackets(String(text[start...end]))
    }

    /// Repairs the structural slips small models make while writing arrays of objects. Only brackets and one stray quote are ever
    /// inserted or dropped; no word is changed. Recognized slips: a missing or extra closing `]`/`}`, a stray quote before an object
    /// (`,"{"id":…`), `]}` written for `}]`, and an array member that starts with a key because its `{` was forgotten (`},"id":"t3",…`). Valid JSON comes
    /// back unchanged with no edits. Output that ends inside a string, or needs more than `maxRecoveryEdits` edits, is rejected.
    static func closingMissingBrackets(_ json: String) -> Extraction? {
        let chars = Array(json)
        var out = ""
        var stack: [Character] = []
        var inString = false, escaped = false
        var edits = 0

        /// Whether the quoted string starting at `start` is an object key (followed by a colon).
        func isKey(at start: Int) -> Bool {
            guard start < chars.count, chars[start] == "\"" else { return false }
            var j = start + 1
            var esc = false
            while j < chars.count {
                if esc { esc = false } else if chars[j] == "\\" { esc = true } else if chars[j] == "\"" { break }
                j += 1
            }
            j += 1
            while j < chars.count, chars[j].isWhitespace { j += 1 }
            return j < chars.count && chars[j] == ":"
        }

        var i = 0
        while i < chars.count {
            let ch = chars[i]
            defer { i += 1 }
            if inString {
                out.append(ch)
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
                continue
            }
            switch ch {
            case "\"":
                if stack.last == "[", let prev = out.last(where: { !$0.isWhitespace }), prev == "," || prev == "[" {
                    // A stray quote directly before an object: `,"{"id":"t2"…`.
                    if i + 2 < chars.count, chars[i + 1] == "{", isKey(at: i + 2) { edits += 1; continue }
                    // An object member written without its brace: `,"id":"t3"…`.
                    if prev == ",", isKey(at: i) { out.append("{"); stack.append("{"); edits += 1 }
                }
                inString = true; out.append(ch)
            case "{", "[": stack.append(ch); out.append(ch)
            case "}", "]":
                let wanted: Character = ch == "}" ? "{" : "["
                // A closer with nothing left to close ("…"}}" for "…"]}") is dropped.
                if stack.isEmpty { edits += 1; continue }
                // The root closing early while more members follow: the model wrote `]}` where `}]` was meant, so this `}` is stray.
                if ch == "}", stack.count == 1, chars[(i + 1)...].contains(where: { !$0.isWhitespace }) { edits += 1; continue }
                if let top = stack.last, top != wanted, stack.contains(wanted) {
                    // Close the inner containers that were left open before this closer.
                    while let open = stack.last, open != wanted { out.append(open == "[" ? "]" : "}"); stack.removeLast(); edits += 1 }
                }
                if stack.last == wanted { stack.removeLast() } else { edits += 1; continue }
                out.append(ch)
            default: out.append(ch)
            }
        }
        if inString { return nil }
        while let open = stack.popLast() { out.append(open == "[" ? "]" : "}"); edits += 1 }
        return edits <= maxRecoveryEdits ? Extraction(json: out, edits: edits) : nil
    }
}

/// Detects when a streamed completion has finished its top-level JSON object, so generation can stop
/// instead of spending tokens on trailing text. Reasoning blocks are skipped.
public struct JSONObjectEndDetector: Sendable {
    private var text = ""
    private var scanned: String.Index
    private var depth = 0
    private var inString = false
    private var escaped = false

    public init() { scanned = text.startIndex }

    /// Appends a chunk; returns true once the first complete top-level object has closed.
    public mutating func feed(_ chunk: String) -> Bool {
        text += chunk
        if let close = text.range(of: "</think>", options: [.caseInsensitive, .backwards]), scanned < close.upperBound {
            scanned = close.upperBound
            depth = 0; inString = false; escaped = false
        } else if scanned == text.startIndex, text.range(of: "<think>", options: .caseInsensitive) != nil {
            return false
        } else if text.range(of: "<think>", options: [.caseInsensitive, .backwards]) != nil,
                  text.range(of: "</think>", options: .caseInsensitive) == nil {
            return false
        }
        while scanned < text.endIndex {
            let ch = text[scanned]
            scanned = text.index(after: scanned)
            if inString {
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
            } else if ch == "\"" {
                inString = true
            } else if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 { return true }
                if depth < 0 { depth = 0 }
            }
        }
        return false
    }
}
