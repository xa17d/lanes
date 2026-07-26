//
//  LaneLibrary.swift
//  Lanes
//
//  Observable wrapper over LaneFS. Holds the configurable root (the only
//  global setting) and re-scans on demand so external renames are picked up.
//

import Foundation
import Combine

@MainActor
final class LaneLibrary: ObservableObject {
    private static let rootDefaultsKey = "rootPath"

    @Published private(set) var root: URL?

    /// True when the root came from the `LANES_ROOT` dev/test override. While
    /// locked the root is **not** persisted and `setRoot` is a no-op, so a test
    /// run can never overwrite the user's stored root.
    private(set) var isRootLocked = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let path = defaults.string(forKey: Self.rootDefaultsKey) {
            self.root = URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    private let defaults: UserDefaults

    func setRoot(_ url: URL) {
        guard !isRootLocked else { return }   // env override in effect: don't touch stored root
        root = url
        defaults.set(url.path, forKey: Self.rootDefaultsKey)
    }

    /// Apply an in-memory-only root (the `LANES_ROOT` dev/test override) and lock
    /// it, so nothing written this session persists to `UserDefaults`.
    func lockRoot(to url: URL) {
        root = url
        isRootLocked = true
    }

    // MARK: - CRUD (thin wrappers over LaneFS)

    func lanes(archivedOnly: Bool = false) -> [Lane] {
        guard let root else { return [] }
        return LaneFS.lanes(in: root, archivedOnly: archivedOnly)
    }

    func create(name: String) throws -> Lane {
        try LaneFS.create(name: name, in: requireRoot())
    }

    @discardableResult
    func touch(_ lane: Lane) -> Lane {
        (try? LaneFS.touch(lane)) ?? lane
    }

    func archive(_ lane: Lane) throws -> Lane {
        try LaneFS.archive(lane, in: requireRoot())
    }

    func unarchive(_ lane: Lane) throws -> Lane {
        try LaneFS.unarchive(lane, in: requireRoot())
    }

    func rename(_ lane: Lane, to name: String) throws -> Lane {
        try LaneFS.rename(lane, to: name)
    }

    func delete(_ lane: Lane) throws {
        try LaneFS.delete(lane)
    }

    private func requireRoot() throws -> URL {
        guard let root else { throw LaneLibraryError.noRoot }
        return root
    }
}

enum LaneLibraryError: LocalizedError {
    case noRoot
    var errorDescription: String? {
        switch self {
        case .noRoot: return "No root folder is configured."
        }
    }
}
