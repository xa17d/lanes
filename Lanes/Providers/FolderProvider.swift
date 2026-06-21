//
//  FolderProvider.swift
//  Lanes
//
//  Section 2. Lane-root folder actions.
//

import Foundation

nonisolated struct FolderProvider: LaneProvider {
    let section = 2
    var displayName: String { "Folder" }

    func items(for lane: Lane, store: LaneStore, services: Services) async -> [any Item] {
        let url = lane.url
        let laneID = lane.id
        let iterm = services.iterm

        // "Open in Finder" now ships as an example lane-level script-item
        // (see examples/script-items); Open Terminal here keeps the built-in
        // tagged iTerm session reuse.
        return [
            BasicItem(id: "folder:terminal", title: "Open Terminal here", icon: .terminal,
                      run: {
                          try iterm.openOrCreate(laneID: laneID, tag: "shell", cwd: url, command: nil)
                          return .dismiss
                      })
        ]
    }
}
