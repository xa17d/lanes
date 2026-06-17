//
//  TrackManagementProvider.swift
//  lane
//
//  Last section. Surfaces a single "Manage track…" container on a track's own
//  page, drilling one level deeper into the rename/reveal/archive/delete
//  actions — so management lives alongside the track's items (the → menu on the
//  root list stays as a shortcut).
//

import Foundation

nonisolated struct TrackManagementProvider: TrackProvider {
    let section = 100   // always last
    var displayName: String { "Manage" }

    func items(for track: Track, store: TrackStore, services: Services) async -> [any Item] {
        [TrackActions.manageTrackItem(for: track, apps: services.apps)]
    }
}
