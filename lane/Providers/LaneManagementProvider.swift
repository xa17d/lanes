//
//  LaneManagementProvider.swift
//  lane
//
//  Last section. Surfaces a single "Manage lane…" container on a lane's own
//  page, drilling one level deeper into the rename/reveal/archive/delete
//  actions — so management lives alongside the lane's items (the → menu on the
//  root list stays as a shortcut).
//

import Foundation

nonisolated struct LaneManagementProvider: LaneProvider {
    let section = 100   // always last
    var displayName: String { "Manage" }

    func items(for lane: Lane, store: LaneStore, services: Services) async -> [any Item] {
        [LaneActions.manageLaneItem(for: lane, apps: services.apps)]
    }
}
