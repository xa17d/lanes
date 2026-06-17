//
//  AppLauncher.swift
//  lane
//
//  Open paths in named apps and reveal them in Finder.
//

import Foundation
import AppKit

nonisolated struct AppLauncher: Sendable {
    let shell: Shell

    /// `open -a "<app>" "<path>"`; throws a friendly notInstalled error on failure.
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
