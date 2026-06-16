//
//  TrackProvider.swift
//  lane
//
//  App-wide, statically registered. Given a track + its store, produces that
//  track's top-level items. The registry fans out providers only at the
//  track's top level; below that, each item yields its own children.
//

import Foundation

protocol TrackProvider: Sendable {
    nonisolated var section: Int { get }              // ordering of top-level groups
    nonisolated var displayName: String { get }       // for timeout toasts
    nonisolated func items(for track: Track, store: TrackStore, services: Services) async -> [any Item]
}

extension TrackProvider {
    var displayName: String { String(describing: Self.self) }
}

/// One provider's contribution to a track's top level.
nonisolated struct ProviderResult: Sendable {
    let section: Int
    let displayName: String
    let items: [any Item]
    let timedOut: Bool
}
