import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: IslandModel!
    private var controller: IslandController!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = IslandModel()
        self.model = model
        self.controller = IslandController(model: model)
        setupStatusItem()
        // Dev-only: open the settings window straight away.
        if ProcessInfo.processInfo.environment["NOTCH_DEBUG_SETTINGS"] != nil {
            SettingsWindowController.shared.show(model: model)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Notch")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "Notch"
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let open = item("Keep island open", #selector(toggleExpanded), tag: 1)
        menu.addItem(open)
        menu.addItem(.separator())

        let workspaceItem = NSMenuItem(title: "Workspace", action: nil, keyEquivalent: "")
        let workspaceMenu = NSMenu()
        for workspace in Workspace.allCases {
            let entry = item(workspace.title, #selector(selectWorkspace(_:)), tag: 14)
            entry.representedObject = workspace.rawValue
            workspaceMenu.addItem(entry)
        }
        workspaceItem.submenu = workspaceMenu
        menu.addItem(workspaceItem)

        // Tiles: show/hide and size.
        let tilesItem = NSMenuItem(title: "Tiles", action: nil, keyEquivalent: "")
        let tilesMenu = NSMenu()
        for id in TileID.allCases {
            let tileItem = NSMenuItem(title: id.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            let show = item("Show tile", #selector(toggleTile(_:)), tag: 10)
            show.representedObject = id.rawValue
            submenu.addItem(show)
            submenu.addItem(.separator())
            for cells in 1...3 {
                let size = item("\(cells) cell\(cells == 1 ? "" : "s")", #selector(setCells(_:)), tag: 11)
                size.representedObject = [id.rawValue, String(cells)]
                submenu.addItem(size)
            }
            tileItem.submenu = submenu
            tilesMenu.addItem(tileItem)
        }
        tilesMenu.addItem(.separator())
        tilesMenu.addItem(item("Reset layout", #selector(resetTiles), tag: 0))
        tilesItem.submenu = tilesMenu
        menu.addItem(tilesItem)

        let cityItem = item("Weather city…", #selector(editCity), tag: 0)
        menu.addItem(cityItem)

        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        for kind in ThemeKind.allCases {
            let entry = item(kind.title, #selector(setTheme(_:)), tag: 12)
            entry.representedObject = kind.rawValue
            themeMenu.addItem(entry)
        }
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)

        menu.addItem(.separator())

        menu.addItem(item("App grid", #selector(showGrid), tag: 0))
        let diagnostics = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        let diagnosticsMenu = NSMenu()
        diagnosticsMenu.addItem(item("Test peek", #selector(testPeek), tag: 0))
        diagnosticsMenu.addItem(item("Test compact pill", #selector(testCompact), tag: 0))
        diagnosticsMenu.addItem(item("Test permission card", #selector(testPermission), tag: 0))
        diagnosticsMenu.addItem(item("Back to resting", #selector(testResting), tag: 0))
        diagnostics.submenu = diagnosticsMenu
        menu.addItem(diagnostics)

        menu.addItem(.separator())

        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        let login = item("Start at login", #selector(toggleLogin), tag: 13)
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Notch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "", tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.tag = tag
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        let settings = model.settings
        for item in menu.items {
            switch item.tag {
            case 1:  // keep open
                item.state = model.pinned ? .on : .off
            case 12: // theme
                item.state = (item.representedObject as? String) == settings.themeKind.rawValue ? .on : .off
            case 13: // login
                item.state = LaunchAtLogin.isEnabled ? .on : .off
            default: break
            }
            if let submenu = item.submenu, item.title == "Tiles" {
                for (index, id) in TileID.allCases.enumerated() {
                    guard index < submenu.items.count, let tileMenu = submenu.items[index].submenu else { continue }
                    let config = settings.config(id)
                    submenu.items[index].state = config.visible ? .on : .off
                    for entry in tileMenu.items where entry.tag == 11 {
                        let cells = Int((entry.representedObject as? [String])?.last ?? "") ?? 0
                        entry.state = cells == config.cells ? .on : .off
                    }
                }
            }
            if let submenu = item.submenu, item.title == "Workspace" {
                for entry in submenu.items {
                    entry.state = (entry.representedObject as? String) == settings.workspace.rawValue ? .on : .off
                }
            }
            if let submenu = item.submenu, item.title == "Theme" {
                for entry in submenu.items where entry.tag == 12 {
                    entry.state = (entry.representedObject as? String) == settings.themeKind.rawValue ? .on : .off
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func toggleExpanded() { model.toggleExpanded() }
    @objc private func testPeek() { model.demoPeek() }
    @objc private func testCompact() { model.demoCompact() }
    @objc private func testResting() { model.demoResting() }
    @objc private func showGrid() { model.showAppGrid() }

    @objc private func testPermission() {
        let card = PermissionCard(id: "demo", tool: "Bash",
                                  command: "rm -rf ./build && swift build -c release 2>&1 | tail -40",
                                  summary: "rebuild", session: "demo", received: Date())
        model.pinPermission(card)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show(model: model)
    }

    @objc private func editCity() {
        SettingsWindowController.shared.show(model: model)
    }

    @objc private func resetTiles() { model.settings.resetTiles() }

    @objc private func toggleLogin() {
        model.settings.launchAtLogin.toggle()
    }

    @objc private func toggleTile(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = TileID(rawValue: raw) else { return }
        model.settings.toggle(id)
    }

    @objc private func setCells(_ sender: NSMenuItem) {
        guard let parts = sender.representedObject as? [String], parts.count == 2,
              let id = TileID(rawValue: parts[0]), let cells = Int(parts[1]) else { return }
        model.settings.setCells(id, cells)
    }

    @objc private func selectWorkspace(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let workspace = Workspace(rawValue: raw) else { return }
        model.settings.selectWorkspace(workspace)
    }

    @objc private func setTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = ThemeKind(rawValue: raw) else { return }
        model.settings.themeKind = kind
    }
}
