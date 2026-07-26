//
//  LaneManagementProvider.swift
//  Lanes
//
//  Last section. Surfaces a single "Manage lane…" container on a lane's own
//  page, drilling one level deeper into the clone-repo / link-ticket / rename /
//  reveal / archive / delete actions — so the lane's top level holds only
//  actual content and everything you do *to* the lane lives here (the → menu on
//  the root list stays as a shortcut).
//

import Foundation

nonisolated struct LaneManagementProvider: LaneProvider {
    let section = 100   // always last
    var displayName: String { "Manage" }

    func items(for lane: Lane, store: LaneStore, services: Services) async -> [any Item] {
        return [LaneActions.manageLaneItem(for: lane, store: store, apps: services.apps, hooks: services.hooks)]
    }
}
