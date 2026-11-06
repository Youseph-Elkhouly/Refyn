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

    /// The outermost JSON object in the output, or nil when there is none.
    public static func jsonObject(from raw: String) -> String? {
        let text = stripReasoning(raw)
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return String(text[start...end])
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
