import XCTest
@testable import RefineCore
@testable import Refyn

/// The end-to-end evaluation on real Qwen3-4B. Gated: REFINE_RUN_LOCAL_MODEL_EVALUATION=1. FINAL_EVAL_PASSES (default 2) sets the repetitions.
/// Every check compares meaning (MeaningMatch), not literal wording: equivalent phrasing passes, a lost negation, a changed number or a
/// changed identifier fails. The report is written to $FINAL_EVAL_OUTPUT (default /tmp/final-eval.txt).
final class FinalEvaluationTests: XCTestCase {
    struct Case {
        let name: String
        let request: String
        let mode: PromptMode
        /// What the user said that must still be said in the result.
        let keep: [String]
        /// Wordings that would mean the optimizer contradicted or extended the request.
        let forbidden: [String]
        /// Clauses that are legitimate for this request. If the validator removes or rewrites one, that is a false positive.
        let legit: [String]
    }

    static let cases: [Case] = [
        Case(name: "rename", request: "Rename Save to Continue", mode: .auto, keep: ["Save", "Continue"], forbidden: [], legit: []),
        Case(name: "tooltip", request: "add a tooltip to the export button", mode: .auto, keep: ["tooltip", "export"], forbidden: [], legit: []),
        Case(name: "notch animation", request: "the animation for opening the notch is bad", mode: .auto, keep: ["notch"], forbidden: [], legit: []),
        Case(name: "avatar bug", request: "saving a profile sometimes loses the avatar", mode: .auto, keep: ["avatar"], forbidden: ["OAuth"], legit: ["reproduce the avatar loss", "regression test"]),
        Case(name: "dark mode", request: "add dark mode", mode: .basic, keep: ["dark mode"], forbidden: [], legit: []),
        Case(name: "search faster", request: "make search faster but don't change the result order or the public API", mode: .auto,
             keep: ["don't change the result order", "don't change the public API"], forbidden: ["change the public API to", "add a parameter to the public API"], legit: ["measure the current search time"]),
        Case(name: "ambiguous auth", request: "make authentication better", mode: .advanced, keep: ["authentication"],
             forbidden: ["OAuth", "JWT", "MFA", "SSO", "SAML", "TOTP", "two-factor"], legit: ["review the current sign-in flow", "find the code that implements authentication"]),
        Case(name: "token logout", request: "users get logged out after the token expires. fix it but never store tokens in plain text", mode: .auto,
             keep: ["tokens must not be stored in plain text"], forbidden: ["store the token in plain text", "OAuth"], legit: ["reproduce the logout"]),
        Case(name: "typo keep font", request: "fix the typo in the onboarding title and keep the font", mode: .auto, keep: ["typo", "onboarding title", "keep the font"], forbidden: ["change the font"], legit: []),
        Case(name: "image upload retry", request: "image uploads sometimes fail on timeout. add retry but don't retry 4xx responses. keep the current progress UI, max 2 retries, and test timeout, offline, and permanent failure cases. don’t change upload API",
             mode: .advanced, keep: ["timeout", "don't retry 4xx", "keep the current progress UI", "2 retries", "offline", "permanent failure", "don't change upload API"],
             forbidden: ["retry only on 5xx", "retry only", "show retry count", "3 retries", "offline uploads are retried", "retry counter"],
             legit: ["test the permanent failure case", "test the offline case", "test the timeout case", "retry when the request times out", "tests for the timeout"]),
        Case(name: "workspace invites", request: "let workspace admins invite people by email, invites expire after 7 days, add resend and revoke, keep the current settings page layout, and add tests for expiry and duplicate members",
             mode: .advanced, keep: ["7 days", "resend", "revoke", "keep the current settings page layout", "expiry", "duplicate members"], forbidden: ["change the settings page layout"],
             legit: ["tests for expiry", "tests for duplicate members", "resend and revoke"]),
        Case(name: "billing refactor", request: "refactor the billing module to use async/await, don't change the public API, keep the existing tests passing", mode: .auto,
             keep: ["async/await", "don't change the public API", "keep the existing tests passing"], forbidden: ["add a parameter to the public API", "change the public API to"], legit: ["run the existing tests"]),
        Case(name: "header icons", request: "make the settings header feel cleaner but keep the existing icons and don't add new colors", mode: .auto,
             keep: ["keep the existing icons", "don't add new colors"], forbidden: ["replace the icons", "new icon set", "introduce a new color"], legit: ["spacing", "typography"]),
        Case(name: "csv export", request: "add csv export to reports, keep the current filters, don't change the existing report API, and test empty results and very large exports", mode: .advanced,
             keep: ["csv", "keep the current filters", "don't change the existing report API", "empty results", "large exports"], forbidden: ["change the report API to", "add a parameter to the report API"],
             legit: ["test the empty results case", "test the very large exports case", "tests for empty results"]),
        Case(name: "database concurrent timeouts", request: "Database operations are slow, intermittently fail, and time out under concurrent users. Fix the cause without changing the API or breaking anything.",
             mode: .advanced,
             keep: ["database operations are slow", "intermittent failures", "timeout under concurrent users", "without changing the API", "without breaking existing functionality"],
             forbidden: ["unconditionally add indexes", "rebuild database indexes", "no timeout occurs under concurrent load", "significantly faster"],
             legit: ["connection-pool waits or exhaustion", "lock contention", "query plans and access patterns", "same concurrent workload"]),
        Case(name: "date helper", request: "extract date formatting into a helper without changing displayed dates", mode: .basic, keep: ["helper", "without changing displayed dates"], forbidden: ["change the displayed dates to"], legit: ["extract date formatting"]),
    ]

    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[max(0, Int((Double(sorted.count) * p).rounded(.up)) - 1)]
    }

    @MainActor
    func testFinalEvaluation() async throws {
        guard ProcessInfo.processInfo.environment["REFINE_RUN_LOCAL_MODEL_EVALUATION"] == "1" else {
            throw XCTSkip("Set REFINE_RUN_LOCAL_MODEL_EVALUATION=1 to run the final Qwen3-4B evaluation.")
        }
        let passes = Int(ProcessInfo.processInfo.environment["FINAL_EVAL_PASSES"] ?? "") ?? 2
        let manager = LocalModelManager()
        await manager.install()
        guard manager.state == .ready else { throw LLMError.unavailable(manager.state.title) }
        await manager.warmUp()
        let optimizer = PromptOptimizer(provider: LocalLLMProvider(manager: manager))
        let graph = try SemanticEvaluationTests.graph()
        let notes = [Note(workspaceID: UUID(), title: "Speech", body: "Dictation uses a local speech recognizer."),
                     Note(workspaceID: UUID(), title: "History", body: "Prompt history keeps 50 entries.")]

        var lines: [String] = []
        var latencies: [String: [Double]] = [:]
        var all: [Double] = []
        var modelLatencies: [Double] = []
        var promptTokens: [Double] = [], outputTokens: [Double] = []
        var runs = 0, modelRuns = 0, fallbacks = 0, retries = 0, jsonRecovered = 0, jsonUnusable = 0, intentFailures = 0, contradictions = 0
        var falsePositives = 0, corrections = 0, inventedTech = 0, genericCriteria = 0, invalidTaskGraphs = 0
        var details: [String] = []

        for pass in 1...passes {
            for c in Self.cases {
                let analysis = RequestAnalysis(c.request)
                let clock = ContinuousClock()
                let start = clock.now
                let plan = try await optimizer.optimize(.init(text: c.request, mode: c.mode, graph: graph, notes: notes, iterationLimit: 2, unansweredQuestions: analysis.gaps.map(\.question)))
                let d = start.duration(to: clock.now)
                let seconds = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
                let trace = plan.trace
                let usedModel = plan.provider != "local"
                runs += 1; all.append(seconds)
                latencies[trace?.tier ?? "?", default: []].append(seconds)
                if usedModel {
                    modelRuns += 1
                    modelLatencies.append(seconds)
                    if let m = manager.lastMetrics { promptTokens.append(Double(m.promptTokens)); outputTokens.append(Double(m.outputTokens)) }
                }
                if trace?.fallbackReason != nil { fallbacks += 1 }
                retries += trace?.retries ?? 0
                if (trace?.jsonRecoveryEdits ?? 0) > 0 { jsonRecovered += 1 }
                jsonUnusable += trace?.events.filter { $0.stage == "model" && $0.outcome == "unusable-output" }.count ?? 0
                genericCriteria += plan.successCriteria.filter(PromptQuality.genericCriterion).count
                if PromptComposer.topologicalOrder(plan.tasks) == nil { invalidTaskGraphs += 1 }

                let prompt = plan.optimizedPrompt
                let lost = c.keep.filter { !MeaningMatch.contains(prompt, $0) }
                // Forbidden wordings are checked clause by clause so a negated sentence ("do not change the layout") is not a contradiction.
                let bad = c.forbidden.filter { phrase in
                    prompt.components(separatedBy: CharacterSet(charactersIn: ".\n;")).contains { clause in MeaningMatch.contains(clause, phrase) && !Lex.hasMarker(clause) }
                }
                let techs = c.forbidden.filter { RequestAnalysis.technologies(in: $0).count > 0 && prompt.contains($0) }
                let fps = (trace?.events.filter { $0.stage == "semantic" } ?? []).filter { e in c.legit.contains { MeaningMatch.contains(e.detail, $0) } }
                intentFailures += lost.isEmpty ? 0 : 1; contradictions += bad.isEmpty ? 0 : 1; inventedTech += techs.count
                falsePositives += fps.count; corrections += trace?.corrections ?? 0
                lines.append(String(format: "pass%d %-20@ %-8@ %6.1fs path=%@ calls=%d retries=%d jsonEdits=%d corrections=%d fallback=%@ lost=%@ contradictions=%@ falsePositives=%d",
                                    pass, c.name as NSString, (trace?.tier ?? "?") as NSString, seconds, usedModel ? "model" : "local", trace?.modelCalls ?? 0, trace?.retries ?? 0,
                                    trace?.jsonRecoveryEdits ?? 0, trace?.corrections ?? 0, trace?.fallbackReason ?? "none", lost.joined(separator: "|"), bad.joined(separator: "|"), fps.count))
                if !(trace?.events.isEmpty ?? true) { details.append("pass\(pass) \(c.name): " + (trace?.events.map { "\($0.stage)/\($0.outcome): \($0.detail.prefix(140))" }.joined(separator: " | ") ?? "")) }
                if pass == 1 || !bad.isEmpty || !lost.isEmpty { details.append("PROMPT [\(c.name)] pass\(pass) bad=\(bad) lost=\(lost)\n\(prompt)\n") }
            }
        }

        var report = lines.joined(separator: "\n") + "\n\n=== SUMMARY ===\n"
        report += "requests=\(runs) modelRuns=\(modelRuns) fallbacks=\(fallbacks) retries=\(retries) jsonRecovered=\(jsonRecovered) jsonUnusableOutputs=\(jsonUnusable)\n"
        report += "intentPreservationFailures=\(intentFailures) contradictoryOutputs=\(contradictions) inventedTechnology=\(inventedTech) validatorCorrections=\(corrections) falsePositiveRemovals=\(falsePositives) genericCriteria=\(genericCriteria) invalidTaskGraphs=\(invalidTaskGraphs)\n"
        report += String(format: "latency all: median=%.1fs p95=%.1fs max=%.1fs\n", Self.percentile(all, 0.5), Self.percentile(all, 0.95), all.max() ?? 0)
        let modelMean = modelLatencies.isEmpty ? 0 : modelLatencies.reduce(0, +) / Double(modelLatencies.count)
        report += String(format: "latency model-backed: n=%d mean=%.2fs median=%.1fs p95=%.1fs\n", modelLatencies.count, modelMean, Self.percentile(modelLatencies, 0.5), Self.percentile(modelLatencies, 0.95))
        for tier in ["simple", "moderate", "complex"] { if let v = latencies[tier] { report += String(format: "latency %@: n=%d median=%.1fs p95=%.1fs\n", tier, v.count, Self.percentile(v, 0.5), Self.percentile(v, 0.95)) } }
        if !promptTokens.isEmpty {
            report += String(format: "tokens (model runs, last call): prompt median=%.0f p95=%.0f, output median=%.0f p95=%.0f\n", Self.percentile(promptTokens, 0.5), Self.percentile(promptTokens, 0.95), Self.percentile(outputTokens, 0.5), Self.percentile(outputTokens, 0.95))
        }
        report += "\n=== TRACES AND PROMPTS ===\n" + details.joined(separator: "\n")
        let path = ProcessInfo.processInfo.environment["FINAL_EVAL_OUTPUT"] ?? "/tmp/final-eval.txt"
        try report.write(toFile: path, atomically: true, encoding: .utf8)
        print("FINAL_EVAL wrote \(path)")
        XCTAssertEqual(fallbacks, 0, "no fallback to the local builder")
        XCTAssertEqual(intentFailures, 0, "every explicit request marker must survive in meaning")
        XCTAssertEqual(contradictions, 0)
        XCTAssertEqual(falsePositives, 0, "the validator must not remove legitimate clauses")
        XCTAssertEqual(inventedTech, 0)
        XCTAssertEqual(genericCriteria, 0, "vague acceptance criteria must be repaired before display")
        XCTAssertEqual(invalidTaskGraphs, 0, "task dependency IDs must form a valid acyclic graph")
    }

    /// Repeats moderate requests (the tier that produced most malformed JSON) and counts, per generation, whether the first output was usable.
    /// Generation uses sampling (temperature 0.2), so the same request can succeed or fail from run to run.
    @MainActor
    func testJSONReliability() async throws {
        guard ProcessInfo.processInfo.environment["REFINE_RUN_LOCAL_MODEL_EVALUATION"] == "1" else { throw XCTSkip("Set REFINE_RUN_LOCAL_MODEL_EVALUATION=1") }
        let repeats = Int(ProcessInfo.processInfo.environment["JSON_EVAL_REPEATS"] ?? "") ?? 6
        let manager = LocalModelManager()
        await manager.install()
        guard manager.state == .ready else { throw LLMError.unavailable(manager.state.title) }
        await manager.warmUp()
        let optimizer = PromptOptimizer(provider: LocalLLMProvider(manager: manager))
        var requests = 0, firstTryUsable = 0, recovered = 0, retried = 0, fallbacks = 0
        var edits: [Int: Int] = [:]
        var reasons: [String] = []
        for text in ["add dark mode", "saving a profile sometimes loses the avatar", "make search faster but don't change the result order or the public API",
                     "Add team invitations to workspace settings", "Refactor the authorization service", "Write tests for CSV export"] {
            for _ in 0..<repeats {
                let a = RequestAnalysis(text)
                let plan = try await optimizer.optimize(.init(text: text, mode: text == "add dark mode" ? .basic : .auto, iterationLimit: 2, unansweredQuestions: a.gaps.map(\.question)))
                guard let trace = plan.trace, trace.modelCalls > 0 else { continue }
                requests += 1
                if trace.retries == 0 { firstTryUsable += 1 }
                if trace.jsonRecoveryEdits > 0 { recovered += 1; edits[trace.jsonRecoveryEdits, default: 0] += 1 }
                retried += trace.retries
                if trace.fallbackReason != nil { fallbacks += 1 }
                reasons += trace.events.filter { $0.outcome == "unusable-output" || $0.outcome == "invalid-plan" }.map { "\(text.prefix(24)): \($0.detail.prefix(160))" }
            }
        }
        var report = "generations=\(requests) firstOutputUsable=\(firstTryUsable) recoveredByRepair=\(recovered) (edits histogram \(edits.sorted { $0.key < $1.key })) retries=\(retried) fallbacks=\(fallbacks)\n"
        report += reasons.joined(separator: "\n")
        try report.write(toFile: ProcessInfo.processInfo.environment["JSON_EVAL_OUTPUT"] ?? "/tmp/json-eval.txt", atomically: true, encoding: .utf8)
        XCTAssertEqual(fallbacks, 0, "no fallback to the local builder")
    }
}
