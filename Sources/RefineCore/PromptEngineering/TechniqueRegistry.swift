import Foundation

/// Chooses prompting techniques for a request.
public struct TechniqueRegistry: Sendable {
    public init() {}

    public func select(mode: PromptMode, analysis: RequestAnalysis, custom: Set<PromptTechnique> = [], hasContext: Bool) -> [PromptTechnique] {
        var out: [PromptTechnique]
        switch mode {
        case .custom:
            return PromptTechnique.allCases.filter { custom.contains($0) }
        case .basic:
            out = [.structured, .constraints, .outputFormat]
            if hasContext { out.append(.contextInjection) }
        case .advanced:
            out = [.role, .structured, .constraints, .decomposition, .dependencyPlanning, .multiStage, .verification,
                   .acceptanceCriteria, .boundedIteration, .selfCritique, .toolUse, .outputFormat]
            if hasContext { out.append(.contextInjection) }
            if analysis.hasConditions { out.append(.conditionalBranching) }
            if analysis.complexity >= 7 { out.append(.promptChaining) }
        case .auto:
            switch analysis.complexity {
            case ..<2:
                out = [.zeroShot]
                if hasContext { out.append(.contextInjection) }
                if !analysis.constraints.isEmpty { out.append(.constraints) }
            case 2..<5:
                out = [.role, .structured, .constraints, .decomposition, .acceptanceCriteria, .outputFormat]
                if hasContext { out.append(.contextInjection) }
                if analysis.mentionsTests || analysis.taskType == .bugfix { out.append(.verification) }
            default:
                out = [.role, .structured, .constraints, .decomposition, .dependencyPlanning, .multiStage, .verification,
                       .acceptanceCriteria, .boundedIteration, .selfCritique, .outputFormat]
                if hasContext { out.append(.contextInjection) }
                if analysis.complexity >= 8 { out.append(.promptChaining) }
            }
            if analysis.hasConditions { out.append(.conditionalBranching) }
            if analysis.taskType == .bugfix && !out.contains(.boundedIteration) && analysis.complexity >= 2 { out.append(.boundedIteration) }
        }
        // Keep the canonical order so prompts are stable for identical inputs.
        return PromptTechnique.allCases.filter { out.contains($0) }
    }
}
