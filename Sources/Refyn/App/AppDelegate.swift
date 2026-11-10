import AppKit
import RefineCore
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    private var model: AppModel!
    private var panel: PanelController!
    private var statusItem: NSStatusItem!
    private let hotKeys = HotKeyCenter()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            model = AppModel(store: try WorkspaceStore())
        } catch {
            let alert = NSAlert()
            alert.messageText = "Refyn could not open its database"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        panel = PanelController(model: model)
        model.onExpand = { [weak self] in self?.panel.expand() }
        model.onCollapse = { [weak self] in self?.panel.collapse() }
        setupMenuBar()
        setupHotKeys()
        UNUserNotificationCenter.current().delegate = self
        observeVoice()
        Task { await model.load() }
        Task { await model.localModel.warmUp() }
        Task { await model.fastModel.warmUp() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        hotKeys.unregisterAll()
        Task {
            await model?.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Refyn")
        let menu = NSMenu()
        menu.addItem(item("Open Refyn", #selector(openPanel), ""))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit Refyn", #selector(quit), "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func openPanel() { panel.expand() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Shortcuts

    func setupHotKeys() {
        hotKeys.onPress = { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggle: panel.toggle()
            case .pushToTalk: model.voice.start(); panel.layout(animated: true)
            }
        }
        hotKeys.onRelease = { [weak self] action in
            guard let self, action == .pushToTalk else { return }
            model.voice.stop()
            panel.layout(animated: true)
        }
        registerHotKeys()
    }

    func registerHotKeys() {
        if !hotKeys.register(.toggle, Preferences.toggleShortcut) { model?.show("The shortcut \(Preferences.toggleShortcut.display) is taken by another app. Choose another in Settings.", .warning) }
        if !hotKeys.register(.pushToTalk, Preferences.pushToTalkShortcut) { model?.show("The dictation shortcut \(Preferences.pushToTalkShortcut.display) is taken. Choose another in Settings.", .warning) }
    }

    /// Keeps the collapsed pill sized for the recording waveform.
    private func observeVoice() {
        withObservationTracking { _ = model.voice.state } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.panel.layout(animated: true)
                self.observeVoice()
            }
        }
    }

    // MARK: Windows

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(model: model, onShortcutsChanged: { [weak self] in self?.registerHotKeys() })
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Settings"
            w.titlebarAppearsTransparent = true
            w.appearance = NSAppearance(named: .aqua)
            w.backgroundColor = .white
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            settingsWindow = w
        }
        if let settingsWindow { panel.presentSecondaryWindow(settingsWindow) }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        // Let AppKit finish ordering the closing window out before raising the notch again.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.settingsWindow?.isVisible != true else { return }
            self.panel.restoreAfterSecondaryWindow()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
        Task { @MainActor [weak self] in self?.panel.expand() }
    }

    func openFolderPanel() -> URL? {
        panel.withoutAutoCollapse {
            let open = NSOpenPanel()
            open.canChooseDirectories = true
            open.canChooseFiles = false
            open.allowsMultipleSelection = false
            open.prompt = "Add Workspace"
            open.message = "Choose a project folder. Refyn reads it but never changes it."
            return open.runModal() == .OK ? open.url : nil
        }
    }
}

/// Lets SwiftUI views reach AppKit-only flows (open panels, windows).
@MainActor
enum AppActions {
    static var delegate: AppDelegate? { NSApp.delegate as? AppDelegate }
    static func chooseFolder() -> URL? { delegate?.openFolderPanel() }
    static func openSettings() { delegate?.openSettings() }
}
