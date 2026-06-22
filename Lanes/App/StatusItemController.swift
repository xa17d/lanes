//
//  StatusItemController.swift
//  Lanes
//
//  Menu-bar status item with Open, Settings, and Quit.
//

import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let onToggle: () -> Void
    private let onSettings: () -> Void
    private let onToggleKeepAwake: () -> Void
    private let onQuit: () -> Void
    private var updateBadge: NSView?
    private var keepAwakeItem: NSMenuItem?

    init(onToggle: @escaping () -> Void,
         onSettings: @escaping () -> Void,
         onToggleKeepAwake: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onSettings = onSettings
        self.onToggleKeepAwake = onToggleKeepAwake
        self.onQuit = onQuit
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            if let image = menuBarIcon(keepAwake: false) {
                button.image = image
            } else {
                button.title = "Lanes"   // fallback if the symbol is unavailable
            }
        }

        let menu = NSMenu()
        menu.addItem(menuItem("Open Lanes", #selector(toggle), key: ""))
        menu.addItem(.separator())
        let keepAwake = menuItem("Keep system awake", #selector(toggleKeepAwake), key: "")
        menu.addItem(keepAwake)
        keepAwakeItem = keepAwake
        menu.addItem(menuItem("Settings…", #selector(settings), key: ","))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Lanes", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    /// Reflect keep-awake state: check the menu item and add a small bolt badge
    /// to the menu-bar icon while sleep is being held off.
    func setKeepAwake(_ active: Bool) {
        keepAwakeItem?.state = active ? .on : .off
        if let image = menuBarIcon(keepAwake: active) { statusItem.button?.image = image }
    }

    /// The menu-bar icon, optionally with a small `bolt.fill` composited into the
    /// bottom-right corner. Returned as a single **template** image so the menu
    /// bar adapts its color (monochrome, no fixed tint).
    private func menuBarIcon(keepAwake: Bool) -> NSImage? {
        guard let base = NSImage(systemSymbolName: "road.lanes", accessibilityDescription: "Lanes") else {
            return nil
        }
        guard keepAwake,
              let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Keeping awake") else {
            base.isTemplate = true
            return base
        }
        let size = base.size
        let composite = NSImage(size: size)
        composite.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size))
        let badge = size.height * 0.6
        bolt.draw(in: NSRect(x: size.width - badge, y: 0, width: badge, height: badge))
        composite.unlockFocus()
        composite.isTemplate = true
        return composite
    }

    /// Show or hide a small orange dot over the menu-bar icon to signal that a
    /// catalog has fetched updates waiting to be applied.
    func setUpdatesAvailable(_ available: Bool) {
        guard let button = statusItem.button else { return }
        if available {
            let dot = updateBadge ?? {
                let view = NSView()
                view.wantsLayer = true
                view.layer?.backgroundColor = NSColor.systemOrange.cgColor
                view.layer?.cornerRadius = 3
                button.addSubview(view)
                updateBadge = view
                return view
            }()
            let bounds = button.bounds
            dot.frame = NSRect(x: bounds.maxX - 7, y: bounds.maxY - 7, width: 6, height: 6)
        } else {
            updateBadge?.removeFromSuperview()
            updateBadge = nil
        }
    }

    private func menuItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggle() { onToggle() }
    @objc private func settings() { onSettings() }
    @objc private func toggleKeepAwake() { onToggleKeepAwake() }
    @objc private func quit() { onQuit() }
}
