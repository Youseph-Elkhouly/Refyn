import CryptoKit
import Foundation

/// The bounded slice of workspace knowledge sent with an optimization request. Never whole files.
public struct RetrievedContext: Codable, Hashable, Sendable {
    public struct Component: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var type: String
        public var path: String
        public var files: [String]
        public var symbols: [String]
        public var routes: [String]
        public var connectsTo: [String]
    }
    public var workspaceName: String
    public var languages: [String]
    public var frameworks: [String]
    public var components: [Component]
    public var notes: [String]
    public var recentChanges: [String]
    public var analyzed: Bool

    public init(workspaceName: String, languages: [String], frameworks: [String], components: [Component], notes: [String], recentChanges: [String], analyzed: Bool) {
        self.workspaceName = workspaceName; self.languages = languages; self.frameworks = frameworks; self.components = components
        self.notes = notes; self.recentChanges = recentChanges; self.analyzed = analyzed
    }

    public var isEmpty: Bool { components.isEmpty && notes.isEmpty && frameworks.isEmpty }
    /// Paths a model may cite. References outside this set are treated as unverified.
    public var knownPaths: Set<String> { Set(components.flatMap { $0.files + [$0.path] }) }

    public var hash: String {
        let data = (try? JSONEncoder.sorted.encode(self)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }
}

public enum ContextRetriever {
    public static let maxComponents = 6
    public static let maxNotesCharacters = 1_500

    /// Ranks graph components by overlap with the request's words and identifiers.
    public static func retrieve(for analysis: RequestAnalysis, workspaceName: String, graph: CodebaseGraph?, notes: [Note], recentChanges: [String]) -> RetrievedContext {
        let words = tokens(analysis.text)
        var scored: [(GraphNode, Int)] = []
        for node in graph?.nodes ?? [] where node.type != .test || analysis.taskType == .test {
            var score = 0
            let haystack = tokens([node.name, node.path] + node.files + node.symbols.map(\.name) + node.routes.map(\.path))
            score += words.intersection(haystack).count * 3
            for term in analysis.keyTerms where node.files.contains(where: { $0.localizedCaseInsensitiveContains(term) }) || node.symbols.contains(where: { $0.name == term }) { score += 5 }
            if analysis.taskType == .ui && node.type == .frontend { score += 1 }
            if analysis.text.localizedCaseInsensitiveContains("api") && node.type == .api { score += 1 }
            if ["database", "db", "schema", "model", "table", "migration"].contains(where: words.contains) && node.type == .database { score += 2 }
            if score > 0 { scored.append((node, score)) }
        }
        let top = scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id < $1.0.id }.prefix(maxComponents).map(\.0)
        let components = top.map { node in
            RetrievedContext.Component(
                id: node.id, name: node.name, type: node.type.rawValue, path: node.path,
                files: Array(node.files.prefix(8)),
                symbols: Array(node.symbols.prefix(10).map { "\($0.kind) \($0.name) (\($0.path):\($0.line))" }),
                routes: node.routes.prefix(8).map { "\($0.method) \($0.path)" },
                connectsTo: graph?.edges.filter { $0.source == node.id }.prefix(6).map { "\($0.relation) \(graph?.node($0.target)?.name ?? $0.target)\($0.verification == .confirmed ? "" : " (\($0.verification.rawValue))")" } ?? [])
        }
        var budget = maxNotesCharacters
        var noteTexts: [String] = []
        for note in notes where note.includeInContext && budget > 0 {
            let text = "\(note.title): \(note.body)".prefix(budget)
            budget -= text.count
            noteTexts.append(String(text))
        }
        return RetrievedContext(
            workspaceName: workspaceName,
            languages: graph?.metadata.languages.filter(\.analyzed).map(\.name) ?? [],
            frameworks: graph?.metadata.frameworks.map(\.name) ?? [],
            components: components, notes: noteTexts, recentChanges: Array(recentChanges.prefix(3)), analyzed: graph != nil)
    }

    static func tokens(_ text: String) -> Set<String> { tokens([text]) }

    static func tokens(_ texts: [String]) -> Set<String> {
        var out = Set<String>()
        for text in texts {
            // Split camelCase and separators so "UserService" matches "user service".
            let spaced = text.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            for t in spaced.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) where t.count >= 3 && !stopWords.contains(String(t)) {
                out.insert(String(t))
            }
        }
        return out
    }

    static let stopWords: Set<String> = ["the", "and", "for", "with", "that", "this", "from", "into", "add", "make", "should", "would", "when", "then", "can", "you", "use", "using", "new", "all", "any", "not", "are", "src", "lib", "index", "swift", "tsx", "app"]
}

/// Generates workspace.md, the human-readable context file stored in Application Support.
public enum WorkspaceDocument {
    public static func render(workspace: Workspace, graph: CodebaseGraph?, notes: [Note], recentChanges: [(date: Date, summary: String)]) -> String {
        var md = "# \(workspace.name)\n\n"
        md += "_Generated by Refine. Path: `\(workspace.path)`. This file is regenerated; edit notes in Refine instead._\n\n"
        guard let graph else {
            md += "## Project overview\n\nNot analyzed yet.\n"
            return md + notesSection(notes)
        }
        let m = graph.metadata
        md += "## Project overview\n\n"
        md += "- Analyzed: \(m.analyzedAt)\(m.snapshot.head.map { " at commit `\($0.prefix(10))`" } ?? "")\(m.snapshot.branch.map { " on `\($0)`" } ?? "")\n"
        md += "- \(m.stats.files) files scanned, \(graph.nodes.count) components, \(graph.edges.count) relationships\n\n"
        md += "## Languages and frameworks\n\n"
        for l in m.languages { md += "- \(l.name): \(l.files) file(s)\(l.analyzed ? "" : " — not analyzed")\n" }
        for f in m.frameworks { md += "- \(f.name) (evidence: `\(f.evidence.display)`)\n" }
        md += "\n## Architecture summary\n\n"
        let byGroup = Dictionary(grouping: graph.nodes, by: \.group)
        for group in byGroup.keys.sorted() {
            md += "- **\(group)**: " + byGroup[group]!.map(\.name).sorted().joined(separator: ", ") + "\n"
        }
        md += "\n## Important modules\n\n"
        let degree = Dictionary(graph.edges.flatMap { [($0.source, 1), ($0.target, 1)] }, uniquingKeysWith: +)
        for node in graph.nodes.filter({ $0.type != .external && $0.type != .test }).sorted(by: { (degree[$0.id] ?? 0) > (degree[$1.id] ?? 0) }).prefix(12) {
            md += "### \(node.name) (\(node.type.rawValue))\n\n"
            md += "- Path: `\(node.path)`, \(node.files.count) file(s)\n"
            if !node.symbols.isEmpty { md += "- Symbols: " + node.symbols.prefix(12).map { "`\($0.name)`" }.joined(separator: ", ") + "\n" }
            let out = graph.edges.filter { $0.source == node.id }
            if !out.isEmpty { md += "- Uses: " + out.map { "\(graph.node($0.target)?.name ?? $0.target)\($0.verification == .confirmed ? "" : " (\($0.verification.rawValue))")" }.joined(separator: ", ") + "\n" }
            md += "\n"
        }
        md += "## Relevant source files\n\n"
        for e in m.entryPoints.prefix(10) { md += "- Entry: `\(e.display)`\(e.detail.map { " — \($0)" } ?? "")\n" }
        let routes = graph.nodes.flatMap { n in n.routes.map { "\($0.method) \($0.path) — `\($0.source.display)`" } }
        md += "\n## Existing APIs\n\n" + (routes.isEmpty ? "None detected.\n" : routes.prefix(40).map { "- \($0)\n" }.joined())
        let models = graph.nodes.flatMap { n in n.evidence.filter { $0.detail?.contains(" model ") == true }.map { "\($0.detail!) — `\($0.display)`" } }
        let dbDeps = graph.nodes.filter { $0.type == .external && $0.group == "Data" }.map(\.name)
        md += "\n## Database structure\n\n"
        md += models.isEmpty && dbDeps.isEmpty ? "None detected.\n" : models.prefix(30).map { "- \($0)\n" }.joined() + (dbDeps.isEmpty ? "" : "- Data dependencies: \(dbDeps.joined(separator: ", "))\n")
        md += "\n## Development constraints\n\n"
        md += "- Refine never modifies this repository; prompts ask agents to change it.\n"
        for w in m.warnings { md += "- Analysis note: \(w)\n" }
        md += notesSection(notes)
        md += "\n## Recent verified changes\n\n"
        md += recentChanges.isEmpty ? "None yet.\n" : recentChanges.prefix(10).map { "- \($0.date.formatted(date: .abbreviated, time: .shortened)): \($0.summary)\n" }.joined()
        return md
    }

    static func notesSection(_ notes: [Note]) -> String {
        let included = notes.filter(\.includeInContext)
        guard !included.isEmpty else { return "\n## User notes\n\nNone.\n" }
        return "\n## User notes\n\n" + included.map { "### \($0.title)\n\n\($0.body)\n\n" }.joined()
    }

    public static func write(_ markdown: String, workspaceID: UUID) throws -> URL {
        let dir = AppPaths.workspaceDirectory(workspaceID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "workspace.md")
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
