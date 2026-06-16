//
//  TrackLibrary.swift
//  lane
//
//  Observable wrapper over TrackFS. Holds the configurable root (the only
//  global setting) and re-scans on demand so external renames are picked up.
//

import Foundation
import Combine

@MainActor
final class TrackLibrary: ObservableObject {
    private static let rootDefaultsKey = "rootPath"

    @Published private(set) var root: URL?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let path = defaults.string(forKey: Self.rootDefaultsKey) {
            self.root = URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    private let defaults: UserDefaults

    func setRoot(_ url: URL) {
        root = url
        defaults.set(url.path, forKey: Self.rootDefaultsKey)
    }

    // MARK: - CRUD (thin wrappers over TrackFS)

    func tracks(includeArchived: Bool = false) -> [Track] {
        guard let root else { return [] }
        return TrackFS.tracks(in: root, includeArchived: includeArchived)
    }

    func create(name: String) throws -> Track {
        try TrackFS.create(name: name, in: requireRoot())
    }

    @discardableResult
    func touch(_ track: Track) -> Track {
        (try? TrackFS.touch(track)) ?? track
    }

    func archive(_ track: Track) throws -> Track {
        try TrackFS.archive(track, in: requireRoot())
    }

    func unarchive(_ track: Track) throws -> Track {
        try TrackFS.unarchive(track, in: requireRoot())
    }

    func rename(_ track: Track, to name: String) throws -> Track {
        try TrackFS.rename(track, to: name)
    }

    func delete(_ track: Track) throws {
        try TrackFS.delete(track)
    }

    private func requireRoot() throws -> URL {
        guard let root else { throw TrackLibraryError.noRoot }
        return root
    }
}

enum TrackLibraryError: LocalizedError {
    case noRoot
    var errorDescription: String? {
        switch self {
        case .noRoot: return "No root folder is configured."
        }
    }
}
