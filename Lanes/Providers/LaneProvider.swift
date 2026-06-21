//
//  LaneProvider.swift
//  Lanes
//
//  App-wide, statically registered. Given a lane + its store, produces that
//  lane's top-level items. The registry fans out providers only at the
//  lane's top level; below that, each item yields its own children.
//

import Foundation

protocol LaneProvider: Sendable {
    nonisolated var section: Int { get }              // ordering of top-level groups
    nonisolated var displayName: String { get }       // for timeout toasts
    nonisolated func items(for lane: Lane, store: LaneStore, services: Services) async -> [any Item]
}

extension LaneProvider {
    var displayName: String { String(describing: Self.self) }
}

/// One provider's contribution to a lane's top level.
nonisolated struct ProviderResult: Sendable {
    let section: Int
    let displayName: String
    let items: [any Item]
    let timedOut: Bool
}
