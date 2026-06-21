//
//  ScriptItemsProvider.swift
//  Lanes
//
//  Section 4. Lane-level custom actions from the root's
//  `.lanes/config/script-items/` (each executable file is one action, run with
//  the lane dir as cwd). Per-repository scripts live under `repository/` and are
//  contributed by RepositoryProvider instead.
//

import Foundation

nonisolated struct ScriptItemsProvider: LaneProvider {
    let section = 4
    var displayName: String { "Scripts" }

    func items(for lane: Lane, store: LaneStore, services: Services) async -> [any Item] {
        let root = LaneActions.root(of: lane)
        return ScriptItems(shell: services.shell).laneItems(root: root, lane: lane)
    }
}
