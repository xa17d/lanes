//
//  AgentsProvider.swift
//  lane
//
//  Section 3. Agents run per lane, at the lane root, cross-repo. Each is a
//  find-or-create on a tagged iTerm session.
//

import Foundation

nonisolated struct AgentsProvider: LaneProvider {
    let section = 3
    var displayName: String { "Agents" }

    func items(for lane: Lane, store: LaneStore, services: Services) async -> [any Item] {
        let url = lane.url
        let laneID = lane.id
        let iterm = services.iterm

        return [
            BasicItem(id: "agent:claude", title: "Claude", icon: .claude,
                      keywords: ["agent", "ai"],
                      run: {
                          try iterm.openOrCreate(laneID: laneID, tag: "claude", cwd: url, command: "claude")
                          return .dismiss
                      }),
            BasicItem(id: "agent:opencode", title: "opencode", icon: .code,
                      keywords: ["agent", "ai"],
                      run: {
                          try iterm.openOrCreate(laneID: laneID, tag: "opencode", cwd: url, command: "opencode")
                          return .dismiss
                      })
        ]
    }
}
