import AppKit

enum AppMenuBuilder {
    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        addAppMenu(to: mainMenu, appName: "Clippie")
        addStandardEditMenu(to: mainMenu)
        addStandardWindowMenu(to: mainMenu)
        return mainMenu
    }

    private static func addAppMenu(to mainMenu: NSMenu, appName: String) {
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        attach(submenu: appMenu, to: mainMenu)
    }

    private static func addStandardEditMenu(to mainMenu: NSMenu) {
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        attach(submenu: editMenu, to: mainMenu)
    }

    private static func addStandardWindowMenu(to mainMenu: NSMenu) {
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        attach(submenu: windowMenu, to: mainMenu)
    }

    private static func attach(submenu: NSMenu, to mainMenu: NSMenu) {
        let item = NSMenuItem()
        mainMenu.addItem(item)
        item.submenu = submenu
        mainMenu.setSubmenu(submenu, for: item)
    }
}
