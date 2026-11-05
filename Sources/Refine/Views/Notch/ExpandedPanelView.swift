import RefineCore
import SwiftUI

struct ExpandedPanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            if let banner = model.banner { BannerView(banner: banner) { model.banner = nil }.transition(.opacity) }
            Group {
                switch model.route {
                case .compose: ComposerView(model: model)
                case .result: ResultView(model: model)
                case .notes: NotesView(model: model)
                case .saved: SavedPromptsView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(model.route)
            .transition(.opacity)
        }
        .foregroundStyle(Theme.text)
        .motion(Theme.Motion.base, value: model.route)
        .motion(Theme.Motion.base, value: model.banner)
        .onExitCommand { model.onCollapse() }
    }

    var header: some View {
        HStack(spacing: Theme.Space.sm) {
            Button { model.route = model.plan != nil && model.route == .compose ? .result : .compose } label: {
                HStack(spacing: 7) {
                    RefineMark(size: 12)
                    Text("Refine").font(Theme.title)
                }
            }
            .buttonStyle(.plain)
            .help(model.route == .compose ? "Back to the last result" : "Back to the editor")
            .accessibilityLabel("Refine")
            .disabled(model.route == .compose && model.plan == nil)

            Rectangle().fill(Theme.border).frame(width: 1, height: 14)
            WorkspaceMenu(model: model)
            if model.analysis == .running {
                StatusIndicator(kind: .busy, label: "Analyzing").help("Analyzing workspace")
            } else if case .failed(let message) = model.analysis {
                Image(systemName: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(Theme.textSecondary).help(message)
            }
            Spacer()
            IconButton(symbol: "note.text", help: "Notes", active: model.route == .notes) { model.route = model.route == .notes ? .compose : .notes }
            IconButton(symbol: "bookmark", help: "Saved prompts", active: model.route == .saved) { model.route = model.route == .saved ? .compose : .saved }
            IconButton(symbol: "gearshape", help: "Settings (⌘,)") { AppActions.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, 14).frame(height: 44)
    }
}

struct BannerView: View {
    let banner: AppModel.Banner
    let dismiss: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                Image(systemName: banner.kind == .info ? "info.circle" : banner.kind == .warning ? "exclamationmark.triangle" : "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(banner.kind == .info ? Theme.textSecondary : Theme.text)
                Text(banner.text).font(Theme.caption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Spacer(minLength: 0)
                IconButton(symbol: "xmark", help: "Dismiss", action: dismiss).scaleEffect(0.8).frame(width: 22, height: 22)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            Hairline()
        }
        .background(Theme.surface)
    }
}

struct WorkspaceMenu: View {
    @Bindable var model: AppModel
    @State private var renaming: Workspace?
    @State private var newName = ""
    @State private var hovering = false

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
                Divider()
                Button("Remove \(ws.name) from Refine", role: .destructive) { Task { await model.remove(ws) } }
            }
        } label: {
            HStack(spacing: 5) {
                Text(model.current?.name ?? "Select workspace").font(Theme.body).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(hovering ? Theme.text : Theme.textSecondary)
            .padding(.horizontal, 8).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(hovering ? Theme.hover : .clear))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .motion(Theme.Motion.fast, value: hovering)
        .help("Switch workspace")
        .popover(item: $renaming) { ws in
            HStack {
                RTextField(placeholder: "Name", text: $newName).frame(width: 200).onSubmit { commit(ws) }
                RButton(title: "Rename", kind: .primary) { commit(ws) }.keyboardShortcut(.defaultAction)
            }.padding(12)
        }
    }

    func commit(_ ws: Workspace) {
        Task { await model.rename(ws, to: newName) }
        renaming = nil
    }
}
