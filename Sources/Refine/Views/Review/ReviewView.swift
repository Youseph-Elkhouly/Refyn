import RefineCore
import SwiftUI

/// What changed since the prompt was handed off. The repository is the evidence; agent output is optional context.
struct ReviewView: View {
    @Bindable var model: AppModel
    @State private var expanded: Set<String> = []

    var body: some View {
        if model.isReviewing {
            LoadingState(label: "Inspecting the repository…")
        } else if let review = model.review, let record = model.execution {
            VStack(alignment: .leading, spacing: 0) {
                summary(review, record).padding(.horizontal, 18).padding(.vertical, 12)
                Hairline()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        architecture(review.architecture)
                        files(review)
                        if !review.changedDependencies.isEmpty { list("Dependency manifests changed", review.changedDependencies) }
                        if !review.changedTests.isEmpty { list("Test files changed", review.changedTests) }
                        VStack(alignment: .leading, spacing: 4) {
                            FieldLabel("Agent output (optional, supporting context only)")
                            REditor(text: $model.agentOutput, placeholder: "Paste the agent's summary…", font: .system(size: 11.5, design: .monospaced), inset: 6)
                                .frame(height: 80)
                                .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.input))
                                .hairlineBorder(Theme.Radius.md)
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 12)
                }
                Hairline()
                HStack(spacing: Theme.Space.sm) {
                    RButton(title: "Refresh", symbol: "arrow.clockwise") { Task { await model.startReview() } }
                    Spacer()
                    RButton(title: "Reject") { Task { await model.rejectReview() } }.help("Keep the verified architecture as it was.")
                    RButton(title: "Confirm and update", symbol: "checkmark", kind: .primary) { Task { await model.confirmReview() } }
                        .disabled(review.files.isEmpty)
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
            }
        } else {
            EmptyState(symbol: "checklist", title: "Nothing to review", detail: "Copy a prompt, run it in your agent, then come back here.")
        }
    }

    func summary(_ r: ChangeReview, _ record: ExecutionRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(r.files.isEmpty ? "No changes since the hand-off" : "\(r.files.count) file\(r.files.count == 1 ? "" : "s") changed since you copied the prompt")
                    .font(Theme.title)
                Spacer()
                Text("handed to \(AgentRegistry.adapter(record.agent).displayName) \(record.createdAt.formatted(.relative(presentation: .named)))")
                    .font(Theme.caption).foregroundStyle(Theme.textMuted)
            }
            if !r.isGitRepository { Text("Not a git repository: changes are detected by file hashes; no line diffs.").font(Theme.caption).foregroundStyle(Theme.textSecondary) }
            if r.headMoved { Text("New commits were made since the hand-off; diffs are against the commit at hand-off.").font(Theme.caption).foregroundStyle(Theme.textSecondary) }
        }
    }

    func architecture(_ d: ArchitectureDiff) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            FieldLabel("Architecture impact")
            if d.isEmpty { Text("No component or relationship changes.").font(Theme.body).foregroundStyle(Theme.textSecondary) }
            ForEach(d.addedNodes) { n in line("plus", "Added \(n.type.rawValue) **\(n.name)**") }
            ForEach(d.removedNodes) { n in line("minus", "Removed **\(n.name)**") }
            ForEach(d.modifiedNodes, id: \.id) { m in line("pencil", "Modified **\(m.name)**" + detail(m)) }
            ForEach(d.addedEdges) { e in
                line("arrow.right", "\(short(e.source)) → \(short(e.target)) \(e.relation)\(e.verification == .confirmed ? "" : " (\(e.verification.rawValue), unverified)")")
            }
            ForEach(d.removedEdges) { e in line("arrow.right", "~~\(short(e.source)) → \(short(e.target))~~ \(e.relation) removed") }
        }
    }

    func detail(_ m: ArchitectureDiff.Modified) -> String {
        var parts: [String] = []
        if !m.addedSymbols.isEmpty { parts.append("+ " + m.addedSymbols.prefix(4).joined(separator: ", ")) }
        if !m.removedSymbols.isEmpty { parts.append("− " + m.removedSymbols.prefix(4).joined(separator: ", ")) }
        if !m.addedRoutes.isEmpty { parts.append("routes + " + m.addedRoutes.joined(separator: ", ")) }
        if !m.removedRoutes.isEmpty { parts.append("routes − " + m.removedRoutes.joined(separator: ", ")) }
        return parts.isEmpty ? "" : " — " + parts.joined(separator: "; ")
    }

    func short(_ id: String) -> String { id.replacingOccurrences(of: "mod:", with: "").replacingOccurrences(of: "ext:", with: "") }

    func line(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Theme.textMuted).font(.system(size: 10, weight: .semibold)).frame(width: 12)
            Text(LocalizedStringKey(text)).font(Theme.body).foregroundStyle(Theme.text)
        }
    }

    func files(_ r: ChangeReview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel("Files")
            ForEach(r.files) { f in
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        if expanded.contains(f.path) { expanded.remove(f.path) } else { expanded.insert(f.path) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(f.kind == .added ? "A" : f.kind == .deleted ? "D" : "M").font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary).frame(width: 12)
                            Text(f.path).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                            if let c = f.component { Chip(text: c) }
                            if f.hadPriorChanges { Chip(text: "had local edits before").help("This file already had uncommitted changes at hand-off; its diff includes them.") }
                            Spacer()
                            if let a = f.additions { Text("+\(a)").foregroundStyle(Theme.text) }
                            if let d = f.deletions { Text("−\(d)").foregroundStyle(Theme.textMuted) }
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if expanded.contains(f.path), !f.patch.isEmpty {
                        ScrollView(.horizontal) {
                            Text(f.patch + (f.patchTruncated ? "\n… (truncated)" : "")).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(8)
                        }
                        .frame(maxHeight: 220)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.input))
                        .hairlineBorder(Theme.Radius.md)
                    }
                }
            }
        }
    }

    func list(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel(title)
            ForEach(items, id: \.self) { Text($0).font(.system(size: 12, design: .monospaced)) }
        }
    }
}
