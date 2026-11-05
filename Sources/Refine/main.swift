import AppKit
import Carbon.HIToolbox
import RefineCore
import SwiftUI

@main
struct RefineApp: App {
    @NSApplicationDelegateAdaptor(RefineAppDelegate.self) private var appDelegate
    var body: some Scene { Settings { SettingsView() } }
}

@MainActor
final class RefineAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let panelState = PanelState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupPanel()
        setupMenuBar()
        registerShortcut()
        NotificationCenter.default.addObserver(self, selector: #selector(shortcutChanged), name: .refineShortcutChanged, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Refine")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Refine", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Refine", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func setupPanel() {
        let content = PromptPanelView(toggle: { [weak self] in self?.togglePanel() }, panelState: panelState)
        let host = NSHostingView(rootView: content)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 650, height: 500), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        positionPanel(expanded: false, animated: false)
    }

    private func positionPanel(expanded: Bool, animated: Bool) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let size = expanded ? NSSize(width: 650, height: 500) : NSSize(width: 190, height: 38)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height - (expanded ? 8 : 3), width: size.width, height: size.height)
        if animated { panel.animator().setFrame(frame, display: true) } else { panel.setFrame(frame, display: true) }
        panel.contentView?.layer?.cornerRadius = expanded ? 22 : 19
        panel.contentView?.layer?.masksToBounds = true
    }

    @objc private func togglePanel() {
        panelState.isExpanded.toggle()
        if panelState.isExpanded { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }
        else { panel.orderOut(nil) }
        positionPanel(expanded: panelState.isExpanded, animated: true)
    }
    @objc private func showPanel() { panelState.isExpanded = true; NSApp.activate(ignoringOtherApps: true); positionPanel(expanded: true, animated: true); panel.makeKeyAndOrderFront(nil) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showSettings() { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }

    private func registerShortcut() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let delegate = Unmanaged<RefineAppDelegate>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in delegate.togglePanel() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        let keyCode = UInt32(UserDefaults.standard.integer(forKey: "hotkeyKeyCode") == 0 ? Int(kVK_Space) : UserDefaults.standard.integer(forKey: "hotkeyKeyCode"))
        let id = EventHotKeyID(signature: OSType(0x52464E45), id: 1)
        RegisterEventHotKey(keyCode, UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }
    @objc private func shortcutChanged() { if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }; registerShortcut() }
}

extension Notification.Name { static let refineShortcutChanged = Notification.Name("RefineShortcutChanged") }

@MainActor
final class PanelState: ObservableObject { @Published var isExpanded = false }

@MainActor
final class PromptViewModel: ObservableObject {
    @Published var input = ""
    @Published var mode: PromptMode = .auto
    @Published var customTechniques = Set<PromptTechnique>()
    @Published var workspace: URL?
    @Published var plan: PromptPlan?
    @Published var error: String?
    private let optimizer = PromptEngineeringService()
    private let store = PromptPlanService()
    func optimize() async {
        do {
            let result = try await optimizer.optimize(input, mode: mode, customTechniques: customTechniques, workspace: workspace)
            try await store.save(result); plan = result; error = nil
        } catch { self.error = "Enter a prompt before optimizing." }
    }
}

struct PromptPanelView: View {
    let toggle: () -> Void
    @ObservedObject var panelState: PanelState
    @StateObject private var model = PromptViewModel()
    @State private var showingImporter = false
    @FocusState private var editorFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            if !panelState.isExpanded {
                Button(action: toggle) { HStack(spacing: 9) { Image(systemName: "sparkle").foregroundStyle(Color(red: 0.75, green: 0.62, blue: 1)); Text("REFINE").font(.system(size: 11, weight: .semibold, design: .rounded)).tracking(1.8); Circle().fill(model.workspace == nil ? .gray : .green).frame(width: 6, height: 6) }.frame(maxWidth: .infinity, maxHeight: .infinity) }.buttonStyle(.plain)
            } else {
                header
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "text.alignleft").foregroundStyle(.white.opacity(0.45))
                        Text("What should your agent change?").font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.76))
                    }
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $model.input).scrollContentBackground(.hidden).font(.system(size: 15)).foregroundStyle(.white).focused($editorFocused).frame(height: 118)
                        if model.input.isEmpty { Text("Describe the task. Keep the rough edges; Refine will shape it.").font(.system(size: 14)).foregroundStyle(.white.opacity(0.28)).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) }
                    }
                    HStack {
                        Picker("Mode", selection: $model.mode) { ForEach(PromptMode.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().fixedSize().tint(Color(red: 0.78, green: 0.68, blue: 1))
                        Spacer()
                        if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
                        Button { Task { await model.optimize() } } label: { Label("Optimize", systemImage: "sparkles").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 13).padding(.vertical, 8) }.buttonStyle(.borderedProminent).tint(Color(red: 0.43, green: 0.31, blue: 0.72)).keyboardShortcut(.return, modifiers: [.command])
                    }
                    if let plan = model.plan {
                        Divider().overlay(.white.opacity(0.1))
                        HStack { Text("REFINED PROMPT").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(.white.opacity(0.42)); Spacer(); Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(plan.optimizedPrompt, forType: .string) } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color(red: 0.78, green: 0.68, blue: 1)) }
                        ScrollView { Text(plan.optimizedPrompt).font(.system(size: 13, design: .monospaced)).foregroundStyle(.white.opacity(0.85)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(maxHeight: 170)
                        HStack { Text(plan.selectedTechniques.map(\.rawValue).joined(separator: " · ")).lineLimit(1); Spacer(); Button("Edit") { model.input = plan.originalPrompt; model.plan = nil; editorFocused = true }.buttonStyle(.plain) }.font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
                    }
                    if model.plan == nil {
                        HStack(spacing: 8) {
                            Button { showingImporter = true } label: { Label(model.workspace?.lastPathComponent ?? "Choose workspace", systemImage: "folder") }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.55))
                            Spacer()
                            Text("⌃⌥Space").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.3))
                        }.font(.system(size: 12))
                    }
                }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 18)
            }
        }
        .frame(width: panelState.isExpanded ? 650 : 190, height: panelState.isExpanded ? 500 : 38, alignment: .top)
        .background(Color(red: 0.075, green: 0.07, blue: 0.095))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.09), lineWidth: 1))
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.folder]) { result in if case .success(let url) = result { model.workspace = url } }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.plan?.id)
    }
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle").foregroundStyle(Color(red: 0.75, green: 0.62, blue: 1))
            Button { showingImporter = true } label: { HStack(spacing: 5) { Text(model.workspace?.lastPathComponent ?? "Select workspace"); Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)) } }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8))
            Spacer()
            Button { model.plan = nil; model.input = "" } label: { Image(systemName: "plus") }.help("New prompt")
            Button(action: toggle) { Image(systemName: "chevron.up") }.help("Collapse Refine")
        }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.6)).padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 6)
    }
}

struct SettingsView: View {
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode = Int(kVK_Space)
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard shortcut").font(.headline)
            Picker("Key", selection: $hotkeyKeyCode) { Text("Control–Option–Space").tag(Int(kVK_Space)); Text("Control–Option–R").tag(Int(kVK_ANSI_R)) }
                .onChange(of: hotkeyKeyCode) { _, _ in NotificationCenter.default.post(name: .refineShortcutChanged, object: nil) }
            Text("Use the shortcut to open or collapse Refine.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 360, height: 150)
    }
}
