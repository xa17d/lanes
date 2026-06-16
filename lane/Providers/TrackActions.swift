//
//  TrackActions.swift
//  lane
//
//  Level-0 actions: "New track…" and the per-track management menu. These
//  operate on the (Sendable, nonisolated) TrackFS layer so their run closures
//  stay @Sendable.
//

import Foundation

nonisolated enum TrackActions {
    static func newTrackRequest(root: URL) -> InputRequest {
        InputRequest(title: "New track", placeholder: "Track name") { name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw InputError(message: "Enter a track name.") }
            let track = try TrackFS.create(name: trimmed, in: root)
            return .enter(track)
        }
    }

    static func newTrackItem(root: URL) -> any Item {
        BasicItem(id: "track:new", title: "New track…", icon: .add,
                  keywords: ["new", "create", "track"],
                  run: { .pushInput(newTrackRequest(root: root)) })
    }

    static func managementItems(for track: Track, root: URL, apps: AppLauncher) -> [any Item] {
        var items: [any Item] = []

        items.append(BasicItem(id: "mgmt:open", title: "Open", icon: .open,
                               run: { .enter(track) }))

        items.append(BasicItem(id: "mgmt:rename", title: "Rename…", icon: .rename,
                               run: {
                                   .pushInput(InputRequest(title: "Rename track",
                                                           placeholder: "New name",
                                                           initialText: track.name) { name in
                                       let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                                       guard !trimmed.isEmpty else { throw InputError(message: "Enter a name.") }
                                       _ = try TrackFS.rename(track, to: trimmed)
                                       return .popToRoot
                                   })
                               }))

        items.append(BasicItem(id: "mgmt:reveal", title: "Reveal in Finder", icon: .reveal,
                               run: { apps.reveal(track.url); return .dismiss }))

        if track.isArchived {
            items.append(BasicItem(id: "mgmt:unarchive", title: "Unarchive", icon: .unarchive,
                                   run: { _ = try TrackFS.unarchive(track, in: root); return .popToRoot }))
        } else {
            items.append(BasicItem(id: "mgmt:archive", title: "Archive", icon: .archive,
                                   run: { _ = try TrackFS.archive(track, in: root); return .popToRoot }))
        }

        items.append(BasicItem(id: "mgmt:delete", title: "Delete…", icon: .trash,
                               run: {
                                   .pushItems(title: "Delete “\(track.name)”?", items: [
                                       BasicItem(id: "mgmt:delete:confirm", title: "Delete permanently",
                                                 icon: .trash,
                                                 run: { try TrackFS.delete(track); return .popToRoot }),
                                       BasicItem(id: "mgmt:delete:cancel", title: "Cancel", icon: .generic,
                                                 run: { .pop }),
                                   ])
                               }))

        return items
    }
}
