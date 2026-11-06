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
