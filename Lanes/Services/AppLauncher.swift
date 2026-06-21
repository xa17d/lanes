//
//  AppLauncher.swift
//  Lanes
//
//  Open paths in named apps and reveal them in Finder.
//

import Foundation
import AppKit

nonisolated struct AppLauncher: Sendable {
    let shell: Shell

    /// `open -a "<app>" "<path>"`; throws a friendly notInstalled error on failure.
    ///
    /// NOTE: unused since the editor/Finder "Open in <app>" actions moved to
    /// example script-items (see `examples/`). Kept as service API for now;
    /// candidate for removal if nothing starts using it again.
    @available(*, deprecated, message: "Unused since launchers moved to script-items; remove if no new callers appear.")
    func open(app: String, path: URL) throws {
        do {
            try shell.run("/usr/bin/open", ["-a", app, path.path])
        } catch {
            throw AutomationError.notInstalled(app: app)
        }
    }

    func reveal(_ path: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([path])
    }
}
