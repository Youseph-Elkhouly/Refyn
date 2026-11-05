import AppKit
import SwiftUI

/// Borderless panel that can take keyboard focus without being a regular window.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Places the panel around the MacBook notch, or as a pill at the top center on displays without one.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let expandedSize = NSSize(width: 660, height: 560)

    let panel: NotchPanel
    private let model: AppModel
    private var previousApp: NSRunningApplication?
    private var hiddenForSecondaryWindow = false
    var suppressAutoCollapse = false

    init(model: AppModel) {
        self.model = model
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.delegate = self
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

    func layout(animated: Bool) {
        guard let screen else { return }
        let g = geometry
        let size: NSSize
        if model.isExpanded {
            size = NSSize(width: Self.expandedSize.width, height: Self.expandedSize.height + (g.hasNotch ? g.notchHeight : 0))
        } else if g.hasNotch {
            let extra: CGFloat = model.voice.isBusy ? 150 : 96
            size = NSSize(width: g.notchWidth + extra, height: g.notchHeight)
        } else {
            size = NSSize(width: model.voice.isBusy ? 230 : 170, height: 30)
        }
        let top = g.hasNotch ? screen.frame.maxY : screen.visibleFrame.maxY - 6
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    func expand() {
        // Keep the secondary window usable while it owns the UI. The global toggle
        // resumes working as soon as that window closes and the panel is restored.
        guard !hiddenForSecondaryWindow else { return }
        guard !model.isExpanded else { panel.makeKey(); return }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }
        model.isExpanded = true
        layout(animated: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Collapses and hands focus back to the app the user was in.
    func collapse(restoreFocus: Bool = true) {
        guard model.isExpanded else { return }
        model.isExpanded = false
        layout(animated: true)
        if restoreFocus, NSApp.isActive, let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
        previousApp = nil
    }

    func toggle() { model.isExpanded ? collapse() : expand() }

    /// Gives Refine's regular windows the screen and keyboard focus. The notch panel is a
    /// status-bar-level window, so merely ordering a regular window forward would leave it
    /// above that window. Hide it until the secondary window closes.
    func prepareForSecondaryWindow() {
        guard !hiddenForSecondaryWindow else { return }
        hiddenForSecondaryWindow = true
        model.isExpanded = false
        panel.orderOut(nil)
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
        // Collapse when focus moves from the panel to any other window. Refine's own
        // secondary windows explicitly hide the panel before they are activated.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.suppressAutoCollapse, self.model.isExpanded,
                  !self.panel.isKeyWindow else { return }
            self.collapse(restoreFocus: false)
        }
    }

    @objc private func screensChanged() { layout(animated: false) }
}
