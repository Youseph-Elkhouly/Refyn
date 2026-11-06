import Foundation

/// How much computation a request deserves. Decided from the local request analysis, with no model call.
public enum OptimizationTier: String, Sendable, Hashable, CaseIterable {
    /// Rewritten instantly by local rules; no model.
    case simple
    /// One compact model call, suited to the small fast model.
    case moderate
    /// The full instructions on the stronger model.
    case complex

    /// Output token budget. Generous relative to measured outputs (about 250–350 and 500–750 tokens), so valid JSON is not cut off.
    public var outputTokenBudget: Int {
        switch self {
        case .simple: 0
        case .moderate: 700
        case .complex: 1300
        }
    }
}

public enum OptimizationRouter {
    /// - Parameters:
    ///   - pendingGaps: unanswered checklist questions for this request.
    ///   - hasLocalCoverage: a model-free recipe or playbook already covers this kind of request (rename, remove, a small UI
    ///     tweak, an animation complaint). Without one, even a short request needs the model to be improved meaningfully.
    ///   - hasAnswers: the user answered at least one clarification.
    public static func tier(analysis: RequestAnalysis, mode: PromptMode, pendingGaps: Int, hasLocalCoverage: Bool = false, hasAnswers: Bool, hasContext: Bool) -> OptimizationTier {
        if mode == .advanced { return .complex }
        let words = analysis.text.split(whereSeparator: \.isWhitespace).count
        var tier: OptimizationTier = switch analysis.complexity {
        case ..<2: .simple
        case 2..<5: .moderate
        default: .complex
        }
        // Anything that needs real reading of the request or the code goes to the model.
        // Open checklist questions alone do not need a model when a local recipe already covers this kind of change.
        let needsModel = (pendingGaps > 0 && !hasLocalCoverage) || hasAnswers || words > 25 || analysis.constraints.count >= 2
            || analysis.hasConditions || (hasContext && analysis.complexity >= 2)
        if (needsModel || !hasLocalCoverage), tier == .simple { tier = .moderate }
        if (words > 40 || analysis.constraints.count >= 3), tier == .moderate { tier = .complex }
        // Basic asks for a lighter result: do not escalate it past moderate unless the request is clearly large.
        if mode == .basic, tier == .complex, analysis.complexity < 7 { tier = .moderate }
        return tier
    }
}
