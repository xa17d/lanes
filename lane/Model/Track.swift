//
//  Track.swift
//  lane
//
//  A track is a self-contained folder. Identity, name, and working dir are all
//  derived from the folder's location/name; only a tiny meta file is persisted.
//

import Foundation

nonisolated struct Track: Identifiable, Hashable, Sendable {
    let url: URL                 // the folder = working dir = the track
    var id: UUID
    var createdAt: Date
    var lastOpenedAt: Date?

    var name: String { url.lastPathComponent }                  // = folder name
    var isArchived: Bool {
        url.deletingLastPathComponent().lastPathComponent == ".archive"
    }
    var dotTrack: URL { url.appendingPathComponent(".track", isDirectory: true) }
}

/// Contents of `.track/track.json`.
nonisolated struct TrackMeta: Codable, Sendable {
    var id: UUID
    var createdAt: Date
    var lastOpenedAt: Date?
}
