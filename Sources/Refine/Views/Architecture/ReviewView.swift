import RefineCore
import SwiftUI

/// What changed since the prompt was handed off. The repository is the evidence; agent output is optional context.
struct ReviewView: View {
    @Bindable var model: AppModel
    @State private var expanded: Set<String> = []

    var body: some View {
        if model.isReviewing {
            VStack(spacing: 10) { ProgressView(); Text("Inspecting the repository…").foregroundStyle(Theme.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let review = model.review, let record = model.execution {
            VStack(alignment: .leading, spacing: 10) {
                summary(review, record)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        architecture(review.architecture)
                        files(review)
                        if !review.changedDependencies.isEmpty { list("Dependency manifests changed", review.changedDependencies) }
                        if !review.changedTests.isEmpty { list("Test files changed", review.changedTests) }
                        VStack(alignment: .leading, spacing: 4) {
                            SectionLabel(text: "Agent output (optional, supporting context only)")
                            TextEditor(text: $model.agentOutput).font(.system(size: 11.5, design: .monospaced)).frame(height: 70)
                                .scrollContentBackground(.hidden).padding(4).background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                        }
                    }
                    .padding(.trailing, 4)
                }
                HStack {
                    Button { Task { await model.startReview() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(PillButtonStyle())
                    Spacer()
                    Button("Reject") { Task { await model.rejectReview() } }.buttonStyle(PillButtonStyle())
                        .help("Keep the verified architecture as it was.")
                    Button { Task { await model.confirmReview() } } label: { Label("Confirm & update architecture", systemImage: "checkmark.seal") }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .disabled(review.files.isEmpty)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        } else {
            ContentUnavailableView("Nothing to review", systemImage: "checklist", description: Text("Copy a prompt, run it in your agent, then come back here."))
        }
    }

    func summary(_ r: ChangeReview, _ record: ExecutionRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(r.files.isEmpty ? "No changes since the hand-off" : "\(r.files.count) file\(r.files.count == 1 ? "" : "s") changed since you copied the prompt")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("handed to \(AgentRegistry.adapter(record.agent).displayName) \(record.createdAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            }
            if !r.isGitRepository { Text("Not a git repository: changes are detected by file hashes; no line diffs.").font(.system(size: 11)).foregroundStyle(Theme.warning) }
            if r.headMoved { Text("New commits were made since the hand-off; diffs are against the commit at hand-off.").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
        }
    }

    func architecture(_ d: ArchitectureDiff) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(text: "Architecture impact")
            if d.isEmpty { Text("No component or relationship changes.").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            ForEach(d.addedNodes) { n in line("plus.circle.fill", Theme.success, "Added \(n.type.rawValue) **\(n.name)**") }
            ForEach(d.removedNodes) { n in line("minus.circle.fill", Theme.danger, "Removed **\(n.name)**") }
            ForEach(d.modifiedNodes, id: \.id) { m in
                line("pencil.circle.fill", Theme.warning, "Modified **\(m.name)**" + detail(m))
            }
            ForEach(d.addedEdges) { e in
                line("arrow.right.circle", e.verification == .confirmed ? Theme.success : Theme.warning,
                     "\(short(e.source)) → \(short(e.target)) \(e.relation)\(e.verification == .confirmed ? "" : " (\(e.verification.rawValue), unverified)")")
            }
            ForEach(d.removedEdges) { e in line("arrow.right.circle", Theme.danger, "~~\(short(e.source)) → \(short(e.target))~~ \(e.relation) removed") }
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

    func line(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color).font(.system(size: 11))
            Text(LocalizedStringKey(text)).font(.system(size: 12))
        }
    }

    func files(_ r: ChangeReview) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(text: "Files")
            ForEach(r.files) { f in
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        if expanded.contains(f.path) { expanded.remove(f.path) } else { expanded.insert(f.path) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(f.kind == .added ? "A" : f.kind == .deleted ? "D" : "M").font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(f.kind == .added ? Theme.success : f.kind == .deleted ? Theme.danger : Theme.warning).frame(width: 12)
                            Text(f.path).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                            if let c = f.component { Chip(text: c) }
                            if f.hadPriorChanges { Chip(text: "had local edits before", color: Theme.warning).help("This file already had uncommitted changes at hand-off; its diff includes them.") }
                            Spacer()
                            if let a = f.additions { Text("+\(a)").foregroundStyle(Theme.success) }
                            if let d = f.deletions { Text("−\(d)").foregroundStyle(Theme.danger) }
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
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
                    }
                }
            }
        }
    }

    func list(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: title)
            ForEach(items, id: \.self) { Text($0).font(.system(size: 12, design: .monospaced)) }
        }
    }
}
