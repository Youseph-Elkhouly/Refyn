import AppKit
import Observation
import RefineCore
import SwiftUI
import UniformTypeIdentifiers

@Observable
@MainActor
final class ArchitectureViewModel {
    let workspace: Workspace
    let appModel: AppModel
    var snapshots: [WorkspaceStore.SnapshotSummary] = []
    var selectedID: UUID?
    var snapshot: ArchitectureSnapshot?
    var diagram: DiagramResult?
    var selectedNodeID: String?
    var highlightChanges = true
    var showPlanned = true
    var showTests = false
    var planned: [PlannedComponent] = []
    var isLoading = false
    var error: String?

    init(workspace: Workspace, appModel: AppModel) {
        self.workspace = workspace
        self.appModel = appModel
    }

    var selectedNode: GraphNode? { selectedNodeID.flatMap { snapshot?.graph.node($0) } }

    func load() async {
        do {
            snapshots = try await appModel.store.snapshotSummaries(workspaceID: workspace.id)
            if snapshots.isEmpty {
                isLoading = true
                await appModel.analyze()
                snapshots = try await appModel.store.snapshotSummaries(workspaceID: workspace.id)
            }
            await select(snapshots.first(where: \.verified)?.id ?? snapshots.first?.id)
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }

    func select(_ id: UUID?) async {
        selectedID = id
        guard let id else { snapshot = nil; diagram = nil; return }
        do {
            snapshot = try await appModel.store.snapshot(id)
            await render()
        } catch { self.error = error.localizedDescription }
    }

    func render() async {
        guard let snapshot else { return }
        isLoading = true
        defer { isLoading = false }
        let options = DiagramOptions(title: "\(workspace.name) · v\(snapshot.version)\(snapshot.verified ? "" : " (unverified)")",
                                     diff: highlightChanges ? snapshot.diff : nil,
                                     planned: showPlanned ? planned : [], showTests: showTests)
        do {
            diagram = try await appModel.architecture.render(snapshot.graph, options: options)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func rescan() async {
        await appModel.analyze()
        if case .failed(let message) = appModel.analysis { error = message }
        await load()
    }

    func exportSVG() {
        guard let svg = diagram?.svg else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.svg]
        panel.nameFieldStringValue = "\(workspace.name)-architecture-v\(snapshot?.version ?? 0).svg"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try svg.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription }
    }
}

struct ArchitectureView: View {
    @Bindable var vm: ArchitectureViewModel

    var body: some View {
        HSplitView {
            history.frame(minWidth: 190, idealWidth: 210, maxWidth: 260)
            ZStack {
                Color(red: 0.055, green: 0.051, blue: 0.075)
                if let diagram = vm.diagram {
                    DiagramWebView(svg: diagram.svg) { elementID in
                        vm.selectedNodeID = elementID.flatMap { diagram.elementIds[$0] }
                    }
                } else if vm.isLoading {
                    ProgressView("Analyzing…")
                } else {
                    ContentUnavailableView("No architecture yet", systemImage: "point.3.connected.trianglepath.dotted", description: Text(vm.error ?? "Analyze the workspace to build its graph."))
                }
                VStack {
                    toolbar
                    Spacer()
                    if let warnings = vm.snapshot?.graph.metadata.warnings, !warnings.isEmpty { warningsView(warnings) }
                }
                .padding(12)
            }
            .frame(minWidth: 560)
            inspector.frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    var toolbar: some View {
        HStack(spacing: 10) {
            Toggle("Highlight changes", isOn: $vm.highlightChanges)
            Toggle("Planned overlay", isOn: $vm.showPlanned).disabled(vm.planned.isEmpty)
            Toggle("Tests", isOn: $vm.showTests)
            Spacer()
            if vm.isLoading { ProgressView().controlSize(.small) }
            if let hidden = vm.diagram?.hidden, hidden > 0 { Text("\(hidden) components not shown").font(.system(size: 11)).foregroundStyle(Theme.tertiary) }
            Button { Task { await vm.rescan() } } label: { Label("Re-analyze", systemImage: "arrow.clockwise") }
            Button { vm.exportSVG() } label: { Label("Export SVG", systemImage: "square.and.arrow.up") }.disabled(vm.diagram == nil)
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 12))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
        .onChange(of: vm.highlightChanges) { Task { await vm.render() } }
        .onChange(of: vm.showPlanned) { Task { await vm.render() } }
        .onChange(of: vm.showTests) { Task { await vm.render() } }
    }

    func warningsView(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Theme.warning) }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
    }

    var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Versions").padding(12)
            List(selection: Binding(get: { vm.selectedID }, set: { id in Task { await vm.select(id) } })) {
                ForEach(vm.snapshots) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("v\(s.version)").font(.system(size: 12, weight: .semibold, design: .monospaced))
                            if !s.verified { Chip(text: "unverified", color: Theme.warning) }
                        }
                        Text(s.label).font(.system(size: 11.5)).lineLimit(2)
                        Text(s.createdAt.formatted(date: .abbreviated, time: .shortened) + (s.head.map { " · \($0.prefix(7))" } ?? ""))
                            .font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
                    }
                    .tag(s.id)
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let node = vm.selectedNode, let graph = vm.snapshot?.graph {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.name).font(.system(size: 16, weight: .semibold))
                        HStack { Chip(text: node.type.rawValue, color: Theme.accent); Chip(text: node.verification.rawValue, color: node.verification == .confirmed ? Theme.success : Theme.warning) }
                        if !node.path.isEmpty { Text(node.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary) }
                    }
                    section("Files", node.files.prefix(30).map { $0 })
                    section("Symbols", node.symbols.prefix(30).map { "\($0.kind) \($0.name) — \($0.path):\($0.line)" })
                    section("Routes", node.routes.map { "\($0.method) \($0.path) — \($0.source.display)" })
                    let connected = graph.edges(touching: node.id)
                    section("Connections", connected.map { e in
                        let other = e.source == node.id ? e.target : e.source
                        return "\(e.source == node.id ? "→" : "←") \(graph.node(other)?.name ?? other) · \(e.relation)\(e.verification == .confirmed ? "" : " (\(e.verification.rawValue))")"
                    })
                    section("Evidence", (node.evidence + connected.flatMap(\.evidence)).prefix(20).map { "\($0.display)\($0.detail.map { " — \($0)" } ?? "")" })
                } else if let graph = vm.snapshot?.graph {
                    Text("Overview").font(.system(size: 16, weight: .semibold))
                    section("Languages", graph.metadata.languages.map { "\($0.name): \($0.files)\($0.analyzed ? "" : " (not analyzed)")" })
                    section("Analysis depth", graph.metadata.supportedLanguages.map { "\($0.name): \($0.level == "syntax" ? "parsed" : "pattern-based")" })
                    section("Frameworks", graph.metadata.frameworks.map { "\($0.name) — \($0.evidence.display)" })
                    section("Entry points", graph.metadata.entryPoints.map(\.display))
                    Text("Solid arrows are confirmed by source evidence; dashed arrows are inferred. Select a component to inspect it.")
                        .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder func section(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                SectionLabel(text: title)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in Text(item).font(.system(size: 11.5, design: .monospaced)).lineLimit(3) }
            }
        }
    }
}
