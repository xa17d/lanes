//
//  ProviderRegistry.swift
//  Lanes
//
//  Static registry of providers, ordered by section. Real providers are
//  registered in Phase 7.
//

import Foundation

nonisolated struct ProviderRegistry: Sendable {
    let providers: [any LaneProvider]

    init(providers: [any LaneProvider]) {
        self.providers = providers.sorted { $0.section < $1.section }
    }

    /// The shipping set of providers, ordered by section.
    static let `default` = ProviderRegistry(providers: [
        TicketProvider(),
        RepositoryProvider(),
        FolderProvider(),
        AgentsProvider(),
        ScriptItemsProvider(),
        LaneManagementProvider(),
    ])
}
