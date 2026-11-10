import AppKit
import SwiftUI

/// Borderless panel that can take keyboard focus without being a regular window.
final class NotchPanel: NSPanel {
    /// True only while open: the expanded content stays mounted when collapsed and must not receive typing.
    var acceptsKeyboard = false
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if !acceptsKeyboard, event.type == .keyDown || event.type == .keyUp { return }
        super.sendEvent(event)
    }
}

/// Places the panel around the MacBook notch, or as a pill at the top center on displays without one.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let expandedSize = NSSize(width: 640, height: 520)
    /// Room around the expanded surface for its shadow.
    private static let shadowMargin: CGFloat = 40

    let panel: NotchPanel
    private let model: AppModel
    private var previousApp: NSRunningApplication?
    private var hiddenForSecondaryWindow = false
    private var surfaceRect = NSRect.zero
    private var settleTask: Task<Void, Never>?
    private var mouseMonitors: [Any] = []
    var suppressAutoCollapse = false

    init(model: AppModel) {
        self.model = model
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.appearance = NSAppearance(named: .aqua)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The surface draws its own shadow: a window shadow would go stale while the surface moves inside the window.
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.delegate = self
        model.onLayoutChange = { [weak self] in self?.layout(animated: true) }
        let root = NotchRootView(model: model, geometry: { [weak self] in self?.geometry ?? .fallback })
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
        layout(animated: false)
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    struct Geometry {
        var hasNotch: Bool
        var notchWidth: CGFloat
        var notchHeight: CGFloat
        static let fallback = Geometry(hasNotch: false, notchWidth: 0, notchHeight: 0)
    }

    /// The built-in display with a notch if there is one, otherwise the display with the active window.
    var screen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first }

    var geometry: Geometry {
        guard let screen, screen.safeAreaInsets.top > 0 else { return .fallback }
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let notchWidth = max(160, screen.frame.width - left - right)
        return Geometry(hasNotch: true, notchWidth: notchWidth, notchHeight: screen.safeAreaInsets.top)
    }

    /// Size of the expanded surface for the current view. Independent of whether the panel is open.
    static func panelSize(model: AppModel, geometry g: Geometry) -> NSSize {
        let contentHeight: CGFloat
        if model.route == .compose {
            if model.clarification != nil { contentHeight = 400 }
            else if model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { contentHeight = 300 }
            else { contentHeight = 380 }
        } else {
            contentHeight = expandedSize.height
        }
        return NSSize(width: expandedSize.width, height: contentHeight + (g.hasNotch ? g.notchHeight : 0))
    }

    static func compactSize(model: AppModel, geometry g: Geometry) -> NSSize {
        // Even, so the centered window lands on a whole point and the surface does not shift when the window trims.
        if g.hasNotch { return NSSize(width: ((g.notchWidth + (model.voice.isBusy ? 150 : 96)) / 2).rounded(.up) * 2, height: g.notchHeight) }
        return NSSize(width: model.voice.isBusy ? 230 : 170, height: 30)
    }

    /// `NotchRootView` animates the visible surface; the window only has to contain it. The window grows once
    /// before a transition and trims once after it settles, so it never resizes while the surface is moving.
    func layout(animated: Bool) {
        guard let screen else { return }
        let g = geometry
        let size = model.isExpanded ? Self.panelSize(model: model, geometry: g) : Self.compactSize(model: model, geometry: g)
        let top = g.hasNotch ? screen.frame.maxY : screen.visibleFrame.maxY - 6
        surfaceRect = NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
        let margin = model.isExpanded ? Self.shadowMargin : 0
        let target = NSRect(x: surfaceRect.minX - margin, y: surfaceRect.minY - margin, width: size.width + margin * 2, height: size.height + margin)

        settleTask?.cancel()
        if model.isExpanded { model.panelContentEnabled = true }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            settle(in: target)
            return
        }
        let spanning = panel.frame.union(target)
        if spanning != panel.frame { panel.setFrame(spanning, display: true) }
        trackMouse()
        let spring = model.isExpanded ? Theme.Motion.surfaceOpen : Theme.Motion.surfaceClose
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(spring.settlingDuration))
            guard !Task.isCancelled else { return }
            self?.settle(in: target)
        }
    }

    private func settle(in target: NSRect) {
        if panel.frame != target { panel.setFrame(target, display: true) }
        model.panelContentEnabled = model.isExpanded
        if model.isExpanded {
            trackMouse()
        } else {
            mouseMonitors.forEach(NSEvent.removeMonitor)
            mouseMonitors = []
            panel.ignoresMouseEvents = false
        }
    }

    /// While the window is larger than the surface, clicks on its transparent part belong to whatever is behind it.
    private func trackMouse() {
        updateMousePassthrough()
        guard mouseMonitors.isEmpty else { return }
        let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            MainActor.assumeIsolated { self?.updateMousePassthrough() }
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMousePassthrough() }
        }
        mouseMonitors = [local, global].compactMap { $0 }
    }

    private func updateMousePassthrough() {
        panel.ignoresMouseEvents = !surfaceRect.insetBy(dx: 0, dy: -1).contains(NSEvent.mouseLocation)
    }

    func expand() {
        // Keep the secondary window usable while it owns the UI. The global toggle
        // resumes working as soon as that window closes and the panel is restored.
        guard !hiddenForSecondaryWindow else { return }
        guard !model.isExpanded else { panel.makeKey(); return }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }
        model.isExpanded = true
        panel.acceptsKeyboard = true
        layout(animated: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Collapses and hands focus back to the app the user was in.
    func collapse(restoreFocus: Bool = true) {
        guard model.isExpanded else { return }
        model.isExpanded = false
        layout(animated: true)
        releaseKeyboard()
        if restoreFocus, NSApp.isActive, let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
    }

    private func releaseKeyboard() {
        panel.makeFirstResponder(nil)
        panel.acceptsKeyboard = false
    }

    func toggle() { model.isExpanded ? collapse() : expand() }

    /// Gives Refyn's regular windows the screen and keyboard focus. The notch panel is a
    /// status-bar-level window, so merely ordering a regular window forward would leave it
    /// above that window. Hide it until the secondary window closes.
    func prepareForSecondaryWindow() {
        guard !hiddenForSecondaryWindow else { return }
        hiddenForSecondaryWindow = true
        model.isExpanded = false
        layout(animated: false)
        releaseKeyboard()
        panel.orderOut(nil)
    }

    /// Hides the higher-level notch panel before activating a regular app window.
    func presentSecondaryWindow(_ window: NSWindow) {
        prepareForSecondaryWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Restore the compact notch affordance after the secondary window goes away.
    func restoreAfterSecondaryWindow() {
        guard hiddenForSecondaryWindow else { return }
        hiddenForSecondaryWindow = false
        layout(animated: false)
        panel.orderFrontRegardless()
    }

    /// Runs a modal sheet-like flow (open panel, alert) without the panel collapsing underneath it.
    func withoutAutoCollapse<T>(_ body: () -> T) -> T {
        suppressAutoCollapse = true
        defer { suppressAutoCollapse = false; panel.makeKey() }
        return body()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard Preferences.collapseOnFocusLoss, !suppressAutoCollapse, model.isExpanded else { return }
        // Collapse when focus moves from the panel to any other window. Refyn's own
        // secondary windows explicitly hide the panel before they are activated.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.suppressAutoCollapse, self.model.isExpanded,
                  !self.panel.isKeyWindow else { return }
            self.collapse(restoreFocus: false)
        }
    }

    @objc private func screensChanged() { layout(animated: false) }
}
