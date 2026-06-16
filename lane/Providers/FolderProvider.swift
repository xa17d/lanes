//
//  FolderProvider.swift
//  lane
//
//  Section 2. Track-root folder actions.
//

import Foundation

nonisolated struct FolderProvider: TrackProvider {
    let section = 2
    var displayName: String { "Folder" }

    func items(for track: Track, store: TrackStore, services: Services) async -> [any Item] {
        let url = track.url
        let trackID = track.id
        let apps = services.apps
        let iterm = services.iterm

        return [
            BasicItem(id: "folder:finder", title: "Open in Finder", icon: .reveal,
                      run: { apps.reveal(url); return .dismiss }),
            BasicItem(id: "folder:terminal", title: "Open Terminal here", icon: .terminal,
                      run: {
                          try iterm.openOrCreate(trackID: trackID, tag: "shell", cwd: url, command: nil)
                          return .dismiss
                      })
        ]
    }
}
