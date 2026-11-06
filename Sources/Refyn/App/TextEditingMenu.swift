import AppKit

/// Adds standard Edit commands so AppKit's focused text controls receive macOS shortcuts.
@MainActor
enum TextEditingMenu {
    static func install(on app: NSApplication) {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(command("Undo", action: "undo:", key: "z"))
        editMenu.addItem(command("Redo", action: "redo:", key: "z", modifiers: [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(command("Cut", action: "cut:", key: "x"))
        editMenu.addItem(command("Copy", action: "copy:", key: "c"))
        editMenu.addItem(command("Paste", action: "paste:", key: "v"))
        editMenu.addItem(command("Select All", action: "selectAll:", key: "a"))

        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        app.mainMenu = mainMenu
    }

    private static func command(_ title: String, action: String, key: String,
                                modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: Selector(action), keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        // A nil target lets AppKit route the action to the focused text view.
        return item
    }
}
