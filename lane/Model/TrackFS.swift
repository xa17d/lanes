//
//  TrackFS.swift
//  lane
//
//  Pure filesystem operations behind TrackLibrary. Foundation-only and
//  isolation-free so the rules (discovery, atomic meta, archive collisions,
//  rename-keeps-id) can be unit-tested directly.
//

import Foundation

nonisolated enum TrackFSError: LocalizedError {
    case alreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .alreadyExists(let name): return "“\(name)” already exists."
        }
    }
}

nonisolated enum TrackFS {
    static let archiveDirName = ".archive"
    static let metaKey = "track"

    private static var fm: FileManager { .default }

    // MARK: - Meta

    private static func metaURL(for trackURL: URL) -> URL {
        trackURL
            .appendingPathComponent(".track", isDirectory: true)
            .appendingPathComponent("\(metaKey).json")
    }

    /// Load a track's meta, creating `track.json` (new UUID, createdAt now) if
    /// it is missing.
    static func loadOrCreateMeta(at trackURL: URL) throws -> TrackMeta {
        let url = metaURL(for: trackURL)
        if let meta = JSONFile.read(TrackMeta.self, at: url) {
            return meta
        }
        let meta = TrackMeta(id: UUID(), createdAt: Date(), lastOpenedAt: nil)
        try JSONFile.writeAtomic(meta, to: url)
        return meta
    }

    private static func track(at url: URL) throws -> Track {
        let meta = try loadOrCreateMeta(at: url)
        return Track(url: url, id: meta.id, createdAt: meta.createdAt, lastOpenedAt: meta.lastOpenedAt)
    }

    // MARK: - Listing

    private static func childDirectories(of dir: URL) -> [URL] {
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter { url in
            // skip dotfiles (belt-and-suspenders with skipsHiddenFiles) and
            // non-directories
            !url.lastPathComponent.hasPrefix(".")
                && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    /// All tracks in `root`, sorted by lastOpenedAt desc (nil last), then name.
    static func tracks(in root: URL, includeArchived: Bool = false) -> [Track] {
        var urls = childDirectories(of: root)
        if includeArchived {
            let archive = root.appendingPathComponent(archiveDirName, isDirectory: true)
            urls += childDirectories(of: archive)
        }
        let loaded = urls.compactMap { try? track(at: $0) }
        return loaded.sorted { a, b in
            switch (a.lastOpenedAt, b.lastOpenedAt) {
            case let (x?, y?): return x == y ? a.name.localizedStandardCompare(b.name) == .orderedAscending : x > y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }

    // MARK: - Mutations

    static func create(name: String, in root: URL) throws -> Track {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let dest = root.appendingPathComponent(name, isDirectory: true)
        guard !fm.fileExists(atPath: dest.path) else { throw TrackFSError.alreadyExists(name) }
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let meta = TrackMeta(id: UUID(), createdAt: Date(), lastOpenedAt: nil)
        try JSONFile.writeAtomic(meta, to: metaURL(for: dest))
        return Track(url: dest, id: meta.id, createdAt: meta.createdAt, lastOpenedAt: nil)
    }

    @discardableResult
    static func touch(_ track: Track, now: Date = Date()) throws -> Track {
        var meta = try loadOrCreateMeta(at: track.url)
        meta.lastOpenedAt = now
        try JSONFile.writeAtomic(meta, to: metaURL(for: track.url))
        return Track(url: track.url, id: meta.id, createdAt: meta.createdAt, lastOpenedAt: now)
    }

    static func archive(_ track: Track, in root: URL) throws -> Track {
        let archiveDir = root.appendingPathComponent(archiveDirName, isDirectory: true)
        try fm.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        let dest = uniqueDestination(in: archiveDir, base: track.name)
        try fm.moveItem(at: track.url, to: dest)
        return try self.track(at: dest)
    }

    static func unarchive(_ track: Track, in root: URL) throws -> Track {
        let dest = uniqueDestination(in: root, base: track.name)
        try fm.moveItem(at: track.url, to: dest)
        return try self.track(at: dest)
    }

    static func rename(_ track: Track, to name: String) throws -> Track {
        let parent = track.url.deletingLastPathComponent()
        let dest = parent.appendingPathComponent(name, isDirectory: true)
        guard !fm.fileExists(atPath: dest.path) else { throw TrackFSError.alreadyExists(name) }
        try fm.moveItem(at: track.url, to: dest)
        // id in track.json keeps identity; reload at the new url.
        return try self.track(at: dest)
    }

    static func delete(_ track: Track) throws {
        try fm.removeItem(at: track.url)
    }

    // MARK: - Helpers

    /// First of `base`, `base-2`, `base-3`, … that does not exist in `dir`.
    private static func uniqueDestination(in dir: URL, base: String) -> URL {
        let first = dir.appendingPathComponent(base, isDirectory: true)
        if !fm.fileExists(atPath: first.path) { return first }
        var n = 2
        while true {
            let candidate = dir.appendingPathComponent("\(base)-\(n)", isDirectory: true)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
