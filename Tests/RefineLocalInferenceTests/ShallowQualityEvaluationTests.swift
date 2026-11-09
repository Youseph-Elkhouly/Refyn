import XCTest
@testable import RefineCore
@testable import Refyn

private actor QualityRecordingProvider: LLMProvider {
    nonisolated let identifier = "quality-evaluation-qwen4b"
    let manager: LocalModelManager
    var stages: [String] = []
    init(_ manager: LocalModelManager) { self.manager = manager }
    func plan(for request: OptimizationRequest) async throws -> ModelPlan {
        let raw = try await manager.generate(request.modelPrompt, maxTokens: request.tier.outputTokenBudget)
        stages.append("RAW\n" + raw)
        guard let extraction = ModelOutput.extract(from: raw) else { throw LLMError.invalidResponse("no JSON") }
        let parsed = try JSONDecoder().decode(ModelPlan.self, from: Data(extraction.json.utf8))
        let schema = try parsed.validated(knownPaths: request.context.knownPaths).0
        let semantic = SemanticValidator.correct(schema, analysis: request.analysis, context: request.context).plan
        let guarded = InventionGuard.apply(to: semantic, analysis: request.analysis, context: request.context, allowedNumbers: [request.iterationLimit]).plan
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for (name, value) in [("PARSED", parsed), ("SCHEMA", schema), ("SEMANTIC", semantic), ("GUARDED", guarded)] {
            stages.append(name + "\n" + String(decoding: try encoder.encode(value), as: UTF8.self))
        }
        return parsed
    }
    func dump() -> String { stages.joined(separator: "\n\n") }
}

final class ShallowQualityEvaluationTests: XCTestCase {
    static let cases = [
        "the notch is kinda buggy and slow sometimes. opening and closing feels weird and some stuff doesnt work properly. test everything and fix whatever is wrong but dont mess up the design.",
        "the app is slow and buggy fix it", "make this ui look better", "my api keeps breaking sometimes",
        "clean up this code without breaking anything", "the animation feels weird", "make login more secure",
        "fix the database stuff it's taking forever",
        "the app is slow when opening windows and switching views. buttons sometimes dont respond and the UI freezes. fix it and dont change the design."
    ]
    private struct ReplayProvider: LLMProvider {
        let identifier = "recorded-qwen4b"
        let value: ModelPlan
        func plan(for request: OptimizationRequest) async throws -> ModelPlan { value }
    }

    private struct RecordedPlan {
        let caseIndex: Int
        let plan: ModelPlan
    }

    private enum ReplayArtifactError: LocalizedError {
        case noCases
        case invalidHeader(String)
        case duplicateCase(Int)
        case missingSection(Int, String)
        case invalidPlan(Int, String)

        var errorDescription: String? {
            switch self {
            case .noCases: "The replay artifact contains no complete CASE records."
            case .invalidHeader(let line): "Invalid replay case header: \(line)"
            case .duplicateCase(let index): "Replay artifact contains duplicate CASE \(index)."
            case .missingSection(let index, let section): "CASE \(index) is missing its \(section) section; the capture may be truncated or malformed."
            case .invalidPlan(let index, let detail): "CASE \(index) has invalid parsed plan JSON: \(detail)"
            }
        }
    }

    /// Parse only complete records and turn malformed captures into actionable test failures, never an array-subscript trap.
    private static func recordedPlans(from artifact: String) throws -> [RecordedPlan] {
        let chunks = artifact.components(separatedBy: "\nCASE ").dropFirst()
        guard !chunks.isEmpty else { throw ReplayArtifactError.noCases }
        var seen = Set<Int>()
        return try chunks.map { chunk in
            let header = chunk.components(separatedBy: .newlines).first ?? ""
            guard let indexText = header.split(separator: " ").first, let index = Int(indexText) else {
                throw ReplayArtifactError.invalidHeader(header)
            }
            guard seen.insert(index).inserted else { throw ReplayArtifactError.duplicateCase(index) }
            guard let parsed = chunk.range(of: "\nPARSED\n") else {
                throw ReplayArtifactError.missingSection(index, "PARSED")
            }
            guard let schema = chunk.range(of: "\nSCHEMA\n", range: parsed.upperBound..<chunk.endIndex) else {
                throw ReplayArtifactError.missingSection(index, "SCHEMA")
            }
            let json = String(chunk[parsed.upperBound..<schema.lowerBound])
            do {
                return RecordedPlan(caseIndex: index, plan: try JSONDecoder().decode(ModelPlan.self, from: Data(json.utf8)))
            } catch {
                throw ReplayArtifactError.invalidPlan(index, String(describing: error))
            }
        }
    }

    func testReplayRecordedBaseline() async throws {
        guard let path = ProcessInfo.processInfo.environment["REFINE_QUALITY_REPLAY"] else { throw XCTSkip("Opt-in replay of recorded Qwen responses") }
        let artifact = try String(contentsOfFile: path, encoding: .utf8)
        let records = try Self.recordedPlans(from: artifact)
        XCTAssertLessThanOrEqual(records.count, Self.cases.count)
        var elapsed = 0.0
        var replayedFinal: [String] = []
        for record in records {
            let index = record.caseIndex
            guard Self.cases.indices.contains(index) else {
                XCTFail("Recorded CASE \(index) has no matching evaluation request.")
                continue
            }
            let start = Date()
            let plan = try await PromptOptimizer(provider: ReplayProvider(value: record.plan)).optimize(.init(text: Self.cases[index], mode: .advanced))
            elapsed += Date().timeIntervalSince(start)
            replayedFinal.append("CASE \(index)\nREQUEST: \(Self.cases[index])\nFINAL_REPLAY\n\(plan.optimizedPrompt)")
            XCTAssertTrue(RequestAnalysis(Self.cases[index]).missingTerms(in: plan.optimizedPrompt).isEmpty,
                          "CASE \(index) dropped original request terms")
            XCTAssertFalse(plan.successCriteria.contains(where: PromptQuality.genericCriterion), "CASE \(index) retained generic acceptance criteria: \(plan.successCriteria)")
            XCTAssertFalse(plan.optimizedPrompt.contains("Example report"), "CASE \(index) added an unrequested report template")
            XCTAssertFalse(plan.optimizedPrompt.range(of: #"(?m)^## Stage \d|^## Fix loop"#, options: .regularExpression) != nil,
                           "CASE \(index) added an unnecessary staged workflow")
            for values in [plan.constraints, plan.successCriteria] {
                for left in values.indices {
                    for right in values.indices where right > left {
                        XCTAssertFalse(PromptOptimizer.semanticallySimilar(values[left], values[right]),
                                       "CASE \(index) repeats a constraint or criterion: \(values[left]) / \(values[right])")
                    }
                }
            }
            for task in plan.tasks { XCTAssertTrue(plan.optimizedPrompt.contains(task.title)) }
            XCTAssertFalse(plan.verificationInstructions.isEmpty)
            if index == Self.cases.count - 1 {
                for symptom in ["opening windows", "switching views", "buttons", "UI freezes"] {
                    XCTAssertTrue(MeaningMatch.contains(plan.optimizedPrompt, symptom), "Recorded CASE \(index) lost symptom: \(symptom)")
                }
            }
        }
        if let output = ProcessInfo.processInfo.environment["REFINE_QUALITY_REPLAY_FINAL_OUTPUT"] {
            try replayedFinal.joined(separator: "\n\n").write(toFile: output, atomically: true, encoding: .utf8)
        }
        print("RECORDED_REPLAY cases=\(records.count) meanPipelineSeconds=\(elapsed / Double(records.count))")
    }

    func testRecordedReplayRejectsTruncatedAndMalformedChunksWithoutCrashing() {
        let missingParsed = "header\nCASE 0 seconds=1.0\nRAW\nresponse without parsed JSON"
        XCTAssertThrowsError(try Self.recordedPlans(from: missingParsed)) { error in
            XCTAssertTrue(error.localizedDescription.contains("CASE 0"))
            XCTAssertTrue(error.localizedDescription.contains("PARSED"))
        }

        let invalidJSON = "header\nCASE 0 seconds=1.0\nPARSED\n{not-json}\nSCHEMA\n{}"
        XCTAssertThrowsError(try Self.recordedPlans(from: invalidJSON)) { error in
            XCTAssertTrue(error.localizedDescription.contains("CASE 0"))
            XCTAssertTrue(error.localizedDescription.contains("invalid parsed plan JSON"))
        }
    }

    @MainActor func testRealVagueRequests() async throws {
        guard ProcessInfo.processInfo.environment["REFINE_RUN_LOCAL_MODEL_EVALUATION"] == "1" else { throw XCTSkip("Opt-in real Qwen evaluation") }
        let manager = LocalModelManager()
        await manager.warmUp()
        let mode: PromptMode = ProcessInfo.processInfo.environment["QUALITY_EVAL_MODE"] == "advanced" ? .advanced : .auto
        var report = "Qwen3-4B / \(mode.rawValue) / no workspace / one sampled run per case\n"
        let output = ProcessInfo.processInfo.environment["QUALITY_EVAL_OUTPUT"] ?? "/tmp/refyn-quality-evaluation.txt"
        for (index, text) in Self.cases.enumerated() {
            let provider = QualityRecordingProvider(manager)
            let start = Date()
            let plan = try await PromptOptimizer(provider: provider).optimize(.init(text: text, mode: mode))
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertTrue(RequestAnalysis(text).missingTerms(in: plan.optimizedPrompt).isEmpty, "CASE \(index) lost request terms")
            XCTAssertFalse(plan.tasks.isEmpty)
            XCTAssertFalse(plan.verificationInstructions.isEmpty)
            XCTAssertFalse(plan.successCriteria.contains(where: PromptQuality.genericCriterion))
            XCTAssertTrue(plan.codeReferences.isEmpty, "No workspace paths were supplied.")
            XCTAssertFalse(plan.optimizedPrompt.contains("Changed: <file>"))
            XCTAssertFalse(plan.optimizedPrompt.contains("Example report"))
            XCTAssertFalse(plan.optimizedPrompt.range(of: #"(?m)^## Stage \d|^## Fix loop"#, options: .regularExpression) != nil)
            for task in plan.tasks { XCTAssertTrue(plan.optimizedPrompt.contains(task.title), "Useful tasks must survive rendering") }
            for step in plan.verificationInstructions { XCTAssertTrue(plan.optimizedPrompt.contains(step), "Checks must survive rendering") }
            for values in [plan.constraints, plan.successCriteria] {
                for left in values.indices {
                    for right in values.indices where right > left {
                        XCTAssertFalse(PromptOptimizer.semanticallySimilar(values[left], values[right]),
                                       "CASE \(index) repeats a constraint or criterion: \(values[left]) / \(values[right])")
                    }
                }
            }
            if index == Self.cases.count - 1 {
                for symptom in ["opening windows", "switching views", "buttons", "UI freezes"] {
                    XCTAssertTrue(MeaningMatch.contains(plan.optimizedPrompt, symptom), "Retain reported symptom: \(symptom)")
                }
            }

            report += "\nCASE \(index) seconds=\(String(format: "%.2f", elapsed)) calls=\(plan.trace?.modelCalls ?? 0) tasks=\(plan.tasks.count) visibleTasks=\(plan.optimizedPrompt.contains("## Tasks") || plan.optimizedPrompt.contains("Stage 2")) verification=\(plan.optimizedPrompt.contains("## Verification") || plan.optimizedPrompt.contains("Stage 3"))\nREQUEST: \(text)\n"
            report += await provider.dump()
            report += "\nFINAL\n\(plan.optimizedPrompt)\nTRACE\n\(String(describing: plan.trace))\n"
            try report.write(toFile: output, atomically: true, encoding: .utf8)
        }
        print("Quality evaluation: \(output)")
    }
}
