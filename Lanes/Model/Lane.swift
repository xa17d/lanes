//
//  Lane.swift
//  Lanes
//
//  A lane is a self-contained folder. Identity, name, and working dir are all
//  derived from the folder's location/name; only a tiny meta file is persisted.
//

import Foundation

nonisolated struct Lane: Identifiable, Hashable, Sendable {
    let url: URL                 // the folder = working dir = the lane
    var id: UUID
    var createdAt: Date
    var lastOpenedAt: Date?
    var summary: String?         // optional one-line description

    var name: String { url.lastPathComponent }                  // = folder name
    var isArchived: Bool {
        // Archived lanes live at <root>/.lanes/archive/<lane>.
        let parent = url.deletingLastPathComponent()
        return parent.lastPathComponent == LaneFS.archiveDirName
            && parent.deletingLastPathComponent().lastPathComponent == LaneFS.lanesDirName
    }
    var dotLane: URL { url.appendingPathComponent(".lane", isDirectory: true) }

    /// The base environment every lane script/hook runs with. Callers layer
    /// their own vars on top (a linked ticket's `TICKET_*`, a repo's `REPO_*`).
    var scriptEnv: [String: String] {
        ["LANE_DIR": url.path, "LANE_NAME": name, "LANE_ID": id.uuidString]
    }
}

nonisolated extension Lane {
    /// Build a lane from its folder location and loaded meta — the single mapping
    /// used by every `LaneFS` op that returns a `Lane`.
    init(url: URL, meta: LaneMeta) {
        self.init(url: url, id: meta.id, createdAt: meta.createdAt,
                  lastOpenedAt: meta.lastOpenedAt, summary: meta.summary)
    }
}

/// Contents of `.lane/lane.json`.
nonisolated struct LaneMeta: Codable, Sendable {
    var id: UUID
    var createdAt: Date
    var lastOpenedAt: Date?
    var summary: String?   // decodes as nil when absent (older files)
}
