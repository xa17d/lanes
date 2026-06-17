//
//  Lane.swift
//  lane
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
        url.deletingLastPathComponent().lastPathComponent == ".archive"
    }
    var dotLane: URL { url.appendingPathComponent(".lane", isDirectory: true) }
}

/// Contents of `.lane/lane.json`.
nonisolated struct LaneMeta: Codable, Sendable {
    var id: UUID
    var createdAt: Date
    var lastOpenedAt: Date?
    var summary: String?   // decodes as nil when absent (older files)
}
