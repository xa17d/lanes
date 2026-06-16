//
//  TrackStore.swift
//  lane
//
//  Per-track key/value store: one JSON file per provider key inside `.track/`.
//  Self-contained, so the whole track moves/renames/deletes as a unit.
//

import Foundation

nonisolated final class TrackStore: Sendable {
    let track: Track

    init(track: Track) {
        self.track = track
    }

    private func url(for key: String) -> URL {
        track.dotTrack.appendingPathComponent("\(key).json")
    }

    func value<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        JSONFile.read(type, at: url(for: key))
    }

    func setValue<T: Encodable>(_ value: T, _ key: String) throws {
        try JSONFile.writeAtomic(value, to: url(for: key))
    }

    func clear(_ key: String) throws {
        let u = url(for: key)
        if FileManager.default.fileExists(atPath: u.path) {
            try FileManager.default.removeItem(at: u)
        }
    }
}
