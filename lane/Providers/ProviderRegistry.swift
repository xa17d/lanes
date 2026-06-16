//
//  ProviderRegistry.swift
//  lane
//
//  Static registry of providers, ordered by section. Real providers are
//  registered in Phase 7.
//

import Foundation

nonisolated struct ProviderRegistry: Sendable {
    let providers: [any TrackProvider]

    init(providers: [any TrackProvider]) {
        self.providers = providers.sorted { $0.section < $1.section }
    }

    /// The shipping set of providers. Populated in Phase 7.
    static let `default` = ProviderRegistry(providers: [])
}
