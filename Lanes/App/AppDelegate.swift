//
//  AppDelegate.swift
//  Lanes
//
//  Owns the status item, global hotkey wiring, and the launcher panel.
//

import AppKit
import Combine
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private let core = AppCore.shared
    private var catalogTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory app: no Dock icon, lives in the menu bar.
        NSApp.setActivationPolicy(.accessory)

        // Dev/test override: LANES_ROOT points the library at a folder without
        // having to configure it in Settings.
        let rootOverride = ProcessInfo.processInfo.environment["LANES_ROOT"]
        if let rootOverride {
            core.library.setRoot(URL(fileURLWithPath: rootOverride, isDirectory: true))
        }
        core.model.onOpenSettings = { AppDelegate.openSettings() }
        core.model.onOpenCatalogSettings = { AppDelegate.openSettings(pane: .catalogs) }

        statusItem = StatusItemController(
            onToggle: { [weak self] in self?.core.panel.toggle(); self?.updateCatalogBadge() },
            onSettings: { AppDelegate.openSettings() },
            onToggleKeepAwake: { [weak self] in self?.core.keepAwake.toggle() },
            onQuit: { NSApp.terminate(nil) }
        )

        // Reflect keep-awake state in the menu bar (checkbox + icon tint). Fires
        // immediately with the current value, so it also sets the initial state.
        core.keepAwake.$isActive
            .sink { [weak self] active in self?.statusItem?.setKeepAwake(active) }
            .store(in: &cancellables)

        // Catalogs fetch in the background (a stale one ~daily) so updates surface
        // as a menu-bar dot; applying them stays an explicit action in Settings.
        refreshCatalogs()
        catalogTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshCatalogs() }
        }

        KeyboardShortcuts.onKeyUp(for: .toggleLane) { [weak self] in
            self?.core.panel.toggle()
        }

        // First launch with no root → prompt for it before showing the list.
        // Deferred so the SwiftUI Settings scene is fully wired before we ask
        // it to open (otherwise the action is a no-op).
        if rootOverride == nil && core.library.root == nil {
            DispatchQueue.main.async { AppDelegate.openSettings() }
        }

        // Debug aid: LANES_AUTOSHOW=1 shows the panel on launch (used for
        // headless smoke tests). Inert without the env var.
        if ProcessInfo.processInfo.environment["LANES_AUTOSHOW"] == "1" {
            core.panel.show()
        }
    }

    static func openSettings(pane: SettingsPane? = nil) {
        AppCore.shared.settings.show(pane: pane)
    }

    /// Fetch stale catalogs off-main, then refresh the menu-bar update dot.
    private func refreshCatalogs() {
        guard let root = core.library.root else { updateCatalogBadge(); return }
        Task.detached {
            Catalogs.fetchAllIfStale(root: root, shell: Shell())
            await MainActor.run { self.updateCatalogBadge() }
        }
    }

    private func updateCatalogBadge() {
        let available = core.library.root.map { Catalogs.anyUpdatesAvailable(root: $0) } ?? false
        statusItem?.setUpdatesAvailable(available)
        core.model.catalogUpdatesAvailable = available
    }
}
