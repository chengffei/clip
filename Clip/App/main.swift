import AppKit
import Darwin

// LSUIElement apps do not get the standard Edit menu automatically, but AppKit
// text controls still rely on it for common key equivalents like Cmd+A/C/V/X.
private func installMinimalEditMenu(on app: NSApplication) {
    let mainMenu = NSMenu()

    let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    let editMenu = NSMenu(title: "Edit")

    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")

    let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redoItem.keyEquivalentModifierMask = [.command, .shift]

    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")

    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)
    app.mainMenu = mainMenu
}

if let exitCode = AgentCommand.runIfRequested(arguments: Array(CommandLine.arguments.dropFirst())) {
    exit(exitCode)
}

let app = NSApplication.shared
installMinimalEditMenu(on: app)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
