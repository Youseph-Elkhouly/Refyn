import AppKit

if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.indices.contains(i + 1) {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    Task { @MainActor in
        await Snapshots.run(into: dir)
        exit(0)
    }
    RunLoop.main.run()
}

// A menu-bar accessory app: no Dock icon, no main window. Everything starts in AppDelegate.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
