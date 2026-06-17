//
//  LaneActions.swift
//  lane
//
//  Level-0 actions: "New lane…" and the per-lane management menu. These
//  operate on the (Sendable, nonisolated) LaneFS layer so their run closures
//  stay @Sendable.
//

import Foundation

nonisolated enum LaneActions {
    static func newLaneRequest(root: URL) -> InputRequest {
        InputRequest(title: "New lane", placeholder: "Lane name") { name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw InputError(message: "Enter a lane name.") }
            let lane = try LaneFS.create(name: trimmed, in: root)
            return .enter(lane)
        }
    }

    static func newLaneItem(root: URL) -> any Item {
        BasicItem(id: "lane:new", title: "New lane…", icon: .add,
                  keywords: ["new", "create", "lane"],
                  run: { .pushInput(newLaneRequest(root: root)) })
    }

    /// The library root that owns `lane`, derived from its location: the
    /// parent folder, or the grandparent when the lane lives under `.archive/`.
    static func root(of lane: Lane) -> URL {
        let parent = lane.url.deletingLastPathComponent()
        return lane.isArchived ? parent.deletingLastPathComponent() : parent
    }

    /// A single "Manage lane…" container drilling into the management actions,
    /// for use from *inside* an already-open lane (so "Open" is omitted).
    static func manageLaneItem(for lane: Lane, apps: AppLauncher) -> any Item {
        let root = root(of: lane)
        return BasicItem(id: "lane:manage", title: "Manage lane…", icon: .manage,
                         keywords: ["manage", "rename", "archive", "delete", "settings"],
                         isSecondary: true,
                         childrenProvider: {
                             managementItems(for: lane, root: root, apps: apps)
                         })
    }

    /// Rename / reveal / archive / delete for a lane. Shown from inside the
    /// lane (via "Manage lane…"), so it does not include an "Open" action.
    static func managementItems(for lane: Lane, root: URL, apps: AppLauncher) -> [any Item] {
        var items: [any Item] = []

        items.append(BasicItem(id: "mgmt:rename", title: "Rename…", icon: .rename,
                               run: {
                                   .pushInput(InputRequest(title: "Rename lane",
                                                           placeholder: "New name",
                                                           initialText: lane.name) { name in
                                       let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                                       guard !trimmed.isEmpty else { throw InputError(message: "Enter a name.") }
                                       _ = try LaneFS.rename(lane, to: trimmed)
                                       return .popToRoot
                                   })
                               }))

        let hasSummary = !(lane.summary ?? "").isEmpty
        items.append(BasicItem(id: "mgmt:describe",
                               title: hasSummary ? "Edit description…" : "Set description…",
                               icon: .note,
                               run: {
                                   .pushInput(InputRequest(title: "Lane description",
                                                           placeholder: "One-line description",
                                                           initialText: lane.summary ?? "") { text in
                                       // Re-enter the lane so the new description
                                       // shows immediately in the header.
                                       let updated = try LaneFS.setSummary(lane, to: text)
                                       return .enter(updated)
                                   })
                               }))

        items.append(BasicItem(id: "mgmt:reveal", title: "Reveal in Finder", icon: .reveal,
                               run: { apps.reveal(lane.url); return .dismiss }))

        if lane.isArchived {
            items.append(BasicItem(id: "mgmt:unarchive", title: "Unarchive", icon: .unarchive,
                                   run: { _ = try LaneFS.unarchive(lane, in: root); return .popToRoot }))
        } else {
            items.append(BasicItem(id: "mgmt:archive", title: "Archive", icon: .archive,
                                   run: { _ = try LaneFS.archive(lane, in: root); return .popToRoot }))
        }

        items.append(BasicItem(id: "mgmt:delete", title: "Delete…", icon: .trash,
                               run: {
                                   .pushItems(title: "Delete “\(lane.name)”?", items: [
                                       BasicItem(id: "mgmt:delete:confirm", title: "Delete permanently",
                                                 icon: .trash,
                                                 run: { try LaneFS.delete(lane); return .popToRoot }),
                                       BasicItem(id: "mgmt:delete:cancel", title: "Cancel", icon: .generic,
                                                 run: { .pop }),
                                   ])
                               }))

        return items
    }
}
