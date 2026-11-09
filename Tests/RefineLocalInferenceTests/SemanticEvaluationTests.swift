import XCTest
@testable import RefineCore
@testable import Refyn

/// Runs the actual Qwen3-4B model on requests whose meaning is easy to get wrong, and checks the final prompt for
/// contradictions, invented UI, unrelated context and lost constraints. Gated: set REFINE_RUN_LOCAL_MODEL_EVALUATION=1.
/// Results are also written to $SEMANTIC_EVAL_OUTPUT (default /tmp/semantic-eval.txt) because a crash at process exit can lose stdout.
final class SemanticEvaluationTests: XCTestCase {
    struct Case {
        let name: String
        let request: String
        let mode: PromptMode
        let retain: [String]
        /// Phrases that would mean the optimizer contradicted, narrowed or extended the request.
        let forbidden: [String]
    }

    static let uploadRequest = "image uploads sometimes fail on timeout. add retry but don't retry 4xx responses. keep the current progress UI, max 2 retries, and test timeout, offline, and permanent failure cases. don’t change upload API"

    static let cases: [Case] = [
        Case(name: "image upload retry", request: uploadRequest, mode: .advanced,
             retain: ["timeout", "4xx", "progress UI", "2 retries", "offline", "permanent failure", "upload API"],
             forbidden: ["retry only on 5xx", "only 5xx", "5xx only", "retry only", "only retry", "reflects retry", "retry counter", "retry count", "retry attempts in the", "3 retries", "automatically retried"]),
        Case(name: "UI keep icons", request: "make the settings header feel cleaner but keep the existing icons and don't add new colors", mode: .auto,
             retain: ["icons", "colors"], forbidden: ["replace the icons", "replace the existing icons", "new icon set"]),
        Case(name: "API refactor", request: "refactor the billing module to use async/await, don't change the public API, keep the existing tests passing", mode: .auto,
             retain: ["async", "public API", "tests"], forbidden: ["add a parameter to the public", "change the public api to"]),
        Case(name: "auth", request: "users get logged out after the token expires. fix it but never store tokens in plain text", mode: .auto,
             retain: ["token", "plain text"], forbidden: ["store the token in plain text", "store tokens in plain text for"]),
        Case(name: "performance", request: "make search faster but don't change the result order or the public API", mode: .auto,
             retain: ["result order", "public API"], forbidden: ["change the public api to"]),
        Case(name: "bug fix", request: "saving a profile sometimes loses the avatar, don't change the profile schema", mode: .auto,
             retain: ["avatar", "schema"], forbidden: ["add a column", "add a field to the profile schema", "alter the schema"]),
    ]

    /// A workspace where only one component concerns uploads; the rest, and the stack, are noise.
    static func graph() throws -> CodebaseGraph {
        let meta = GraphMetadata(workspaceId: "w", analyzedAt: "2026-11-05T00:00:00Z",
                                 snapshot: .init(head: "abc", branch: "main", dirty: false, fingerprint: "f1"),
                                 supportedLanguages: [.init(name: "TypeScript", level: "syntax")],
                                 languages: [.init(name: "TypeScript", files: 4, analyzed: true)],
                                 frameworks: [.init(name: "Express", evidence: SourceRef(path: "package.json"))],
                                 entryPoints: [SourceRef(path: "src/server/index.ts")], warnings: [],
                                 stats: .init(files: 6, reparsed: 6, reused: 0, skipped: 0))
        return CodebaseGraph(schemaVersion: 1, metadata: meta, nodes: [
            GraphNode(id: "mod:src/upload", name: "src/upload", type: .service, path: "src/upload", group: "Services", files: ["src/upload/ImageUploader.ts"],
                      symbols: [GraphSymbol(name: "uploadImage", kind: "function", path: "src/upload/ImageUploader.ts", line: 4)]),
            GraphNode(id: "mod:src/audio", name: "src/audio", type: .service, path: "src/audio", group: "Services", files: ["src/audio/Recorder.ts", "src/audio/SpeechRecognizer.ts"],
                      symbols: [GraphSymbol(name: "transcribeAudio", kind: "function", path: "src/audio/SpeechRecognizer.ts", line: 9)]),
            GraphNode(id: "mod:src/history", name: "src/history", type: .service, path: "src/history", group: "Services", files: ["src/history/PromptHistory.ts"],
                      symbols: [GraphSymbol(name: "savePromptHistory", kind: "function", path: "src/history/PromptHistory.ts", line: 2)]),
        ], edges: [])
    }

    /// A criterion that says the named thing stays as it is, in any wording.
    static func preserves(_ criteria: [String], _ thing: String) -> Bool {
        criteria.contains { c in
            let l = c.lowercased()
            return l.contains(thing) && ["unchanged", "no change", "keep", "remain", "preserve", "not change", "existing signature"].contains { l.contains($0) }
        }
    }

    @MainActor
    func testQwenKeepsMeaningConstraintsAndContext() async throws {
        guard ProcessInfo.processInfo.environment["REFINE_RUN_LOCAL_MODEL_EVALUATION"] == "1" else {
            throw XCTSkip("Set REFINE_RUN_LOCAL_MODEL_EVALUATION=1 to run the semantic fidelity evaluation on Qwen3-4B.")
        }
        let manager = LocalModelManager()
        await manager.install()
        guard manager.state == .ready else { throw LLMError.unavailable(manager.state.title) }
        await manager.warmUp()
        let optimizer = PromptOptimizer(provider: LocalLLMProvider(manager: manager))
        let graph = try Self.graph()
        let notes = [Note(workspaceID: UUID(), title: "Speech", body: "Dictation uses a local speech recognizer."),
                     Note(workspaceID: UUID(), title: "History", body: "Prompt history keeps 50 entries.")]

        var report = ""
        var failures: [String] = []
        for c in Self.cases {
            let clock = ContinuousClock()
            let start = clock.now
            let plan = try await optimizer.optimize(.init(text: c.request, mode: c.mode, graph: graph, notes: notes, iterationLimit: 2))
            let d = start.duration(to: clock.now)
            let elapsed = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
            let prompt = plan.optimizedPrompt
            let lower = prompt.lowercased()
            var checks: [(String, Bool)] = []
            checks.append(("keeps " + c.retain.joined(separator: ", "), c.retain.allSatisfy { MeaningMatch.contains(prompt, $0) }))
            for phrase in c.forbidden { checks.append(("absent: \(phrase)", !lower.contains(phrase.lowercased()))) }
            for unrelated in ["audio", "speech", "prompthistory", "prompt history", "express", "typescript"] {
                checks.append(("unrelated absent: \(unrelated)", !lower.contains(unrelated)))
            }
            checks.append(("only verified paths", !lower.contains("src/audio") && !lower.contains("src/history")))
            if c.name == "image upload retry" {
                checks.append(("timeout retry stated", lower.contains("caused by timeout") || lower.contains("retry") && lower.contains("timeout")))
                checks.append(("two retries = three attempts", lower.contains("3 attempts") || lower.contains("three attempts")))
                checks.append(("scenario: timeout", lower.contains("timeout case")))
                checks.append(("transient vs permanent explained", lower.contains("transient") && lower.contains("permanent failures cannot")))
                checks.append(("scenario: offline observed", lower.contains("offline case") && lower.contains("observed behavior")))
                checks.append(("scenario: permanent failure observed", lower.contains("permanent failure case") && lower.contains("observed behavior")))
                checks.append(("progress UI unchanged", Self.preserves(plan.successCriteria, "progress ui")))
                checks.append(("upload API contract kept", Self.preserves(plan.successCriteria, "upload api")))
                checks.append(("4xx prohibition as criterion", plan.successCriteria.contains { $0.lowercased().contains("4xx") && $0.lowercased().contains("retr") }))
                checks.append(("focused length", prompt.count < 4_500))
            }
            report += "=== \(c.name) [\(c.mode.rawValue)] \(String(format: "%.1f", elapsed))s provider=\(plan.provider) chars=\(prompt.count)\n"
            report += "REQUEST: \(c.request)\nNOTICES: \(plan.notices.joined(separator: " | "))\n\(prompt)\n"
            for (name, ok) in checks where !ok { report += "CHECK FAILED: \(name)\n"; failures.append("\(c.name): \(name)") }
            report += "checks: \(checks.filter(\.1).count)/\(checks.count)\n\n"
        }
        report += "TOTAL FAILED CHECKS: \(failures.count)\n"
        let path = ProcessInfo.processInfo.environment["SEMANTIC_EVAL_OUTPUT"] ?? "/tmp/semantic-eval.txt"
        try report.write(toFile: path, atomically: true, encoding: .utf8)
        print("SEMANTIC_EVAL wrote \(path); failed checks: \(failures.count)")
        XCTAssertTrue(failures.isEmpty, "Failed checks: \(failures.joined(separator: "; "))")
    }
}
