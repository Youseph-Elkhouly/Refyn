import RefineCore
import SwiftUI

struct ExpandedPanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            if let banner = model.banner { BannerView(banner: banner) { model.banner = nil } }
            Group {
                switch model.route {
                case .compose: ComposerView(model: model)
                case .result: ResultView(model: model)
                case .notes: NotesView(model: model)
                case .saved: SavedPromptsView(model: model)
                case .review: ReviewView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(Theme.text)
        .onExitCommand { model.onCollapse() }
    }

    var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent).padding(.trailing, 2)
            WorkspaceMenu(model: model)
            if model.analysis == .running {
                ProgressView().controlSize(.mini).help("Analyzing workspace")
            } else if case .failed(let message) = model.analysis {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Theme.warning).help(message)
            }
            Spacer()
            IconButton(symbol: "square.and.pencil", help: "New prompt", active: model.route == .compose) {
                if model.route == .compose { model.input = ""; model.plan = nil }
                model.route = .compose
            }
            IconButton(symbol: "note.text", help: "Notes", active: model.route == .notes) { model.route = model.route == .notes ? .compose : .notes }
            IconButton(symbol: "bookmark", help: "Saved prompts", active: model.route == .saved) { model.route = model.route == .saved ? .compose : .saved }
            IconButton(symbol: "point.3.connected.trianglepath.dotted", help: "Architecture") { model.visualize() }
            IconButton(symbol: "gearshape", help: "Settings") { AppActions.openSettings() }
            IconButton(symbol: "chevron.up", help: "Collapse (Esc)") { model.onCollapse() }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }
}

struct BannerView: View {
    let banner: AppModel.Banner
    let dismiss: () -> Void
    var color: Color { banner.kind == .error ? Theme.danger : banner.kind == .warning ? Theme.warning : Theme.accent }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: banner.kind == .info ? "info.circle" : "exclamationmark.triangle").foregroundStyle(color)
            Text(banner.text).font(.system(size: 12)).foregroundStyle(Theme.text.opacity(0.85)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }.buttonStyle(.plain).foregroundStyle(Theme.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(color.opacity(0.08))
    }
}

struct WorkspaceMenu: View {
    @Bindable var model: AppModel
    @State private var renaming: Workspace?
    @State private var newName = ""

    var body: some View {
        Menu {
            ForEach(model.workspaces) { ws in
                Button { Task { await model.select(ws) } } label: {
                    if ws.id == model.current?.id { Label(ws.name, systemImage: "checkmark") } else { Text(ws.name) }
                }
            }
            if !model.workspaces.isEmpty { Divider() }
            Button("Add Workspace…") { if let url = AppActions.chooseFolder() { Task { await model.addWorkspace(url) } } }
            if let ws = model.current {
                Button("Re-analyze \(ws.name)") { Task { await model.analyze() } }
                Button("Rename \(ws.name)…") { newName = ws.name; renaming = ws }
                Button("Reveal workspace.md") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.workspaceDirectory(ws.id).appending(path: "workspace.md")]) }
                Divider()
                Button("Remove \(ws.name) from Refine", role: .destructive) { Task { await model.remove(ws) } }
            }
        } label: {
            HStack(spacing: 5) {
                Text(model.current?.name ?? "Select workspace").font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Theme.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .popover(item: $renaming) { ws in
            HStack {
                TextField("Name", text: $newName).textFieldStyle(.roundedBorder).frame(width: 200).onSubmit { commit(ws) }
                Button("Rename") { commit(ws) }.keyboardShortcut(.defaultAction)
            }.padding(12)
        }
    }

    func commit(_ ws: Workspace) {
        Task { await model.rename(ws, to: newName) }
        renaming = nil
    }
}
