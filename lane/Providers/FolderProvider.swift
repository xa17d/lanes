//
//  FolderProvider.swift
//  lane
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
        let apps = services.apps
        let iterm = services.iterm

        return [
            BasicItem(id: "folder:finder", title: "Open in Finder", icon: .reveal,
                      run: { apps.reveal(url); return .dismiss }),
            BasicItem(id: "folder:terminal", title: "Open Terminal here", icon: .terminal,
                      run: {
                          try iterm.openOrCreate(laneID: laneID, tag: "shell", cwd: url, command: nil)
                          return .dismiss
                      })
        ]
    }
}
