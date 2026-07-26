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

    func reveal(_ path: URL) {
        // Run closures now execute off the main actor, but AppKit wants this on
        // main.
        DispatchQueue.main.async {
            NSWorkspace.shared.activateFileViewerSelecting([path])
        }
    }
}
