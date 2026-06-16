//
//  AgentsProvider.swift
//  lane
//
//  Section 3. Agents run per track, at the track root, cross-repo. Each is a
//  find-or-create on a tagged iTerm session.
//

import Foundation

nonisolated struct AgentsProvider: TrackProvider {
    let section = 3
    var displayName: String { "Agents" }

    func items(for track: Track, store: TrackStore, services: Services) async -> [any Item] {
        let url = track.url
        let trackID = track.id
        let iterm = services.iterm

        return [
            BasicItem(id: "agent:claude", title: "Claude", icon: .claude,
                      keywords: ["agent", "ai"],
                      run: {
                          try iterm.openOrCreate(trackID: trackID, tag: "claude", cwd: url, command: "claude")
                          return .dismiss
                      }),
            BasicItem(id: "agent:opencode", title: "opencode", icon: .code,
                      keywords: ["agent", "ai"],
                      run: {
                          try iterm.openOrCreate(trackID: trackID, tag: "opencode", cwd: url, command: "opencode")
                          return .dismiss
                      })
        ]
    }
}
