//
//  StatusItemController.swift
//  lane
//
//  Menu-bar status item with Open, Settings, and Quit.
//

import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let onToggle: () -> Void
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    init(onToggle: @escaping () -> Void,
         onSettings: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onSettings = onSettings
        self.onQuit = onQuit
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "road.lanes", accessibilityDescription: "Lanes") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "Lanes"   // fallback if the symbol is unavailable
            }
        }

        let menu = NSMenu()
        menu.addItem(menuItem("Open Lanes", #selector(toggle), key: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", #selector(settings), key: ","))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Lanes", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func menuItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggle() { onToggle() }
    @objc private func settings() { onSettings() }
    @objc private func quit() { onQuit() }
}
