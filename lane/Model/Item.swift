//
//  Item.swift
//  lane
//
//  The one universal node. Optional `run` (leaf = action) and `children()`
//  (container). A provider owns its entire subtree.
//

import Foundation

nonisolated enum RunOutcome: Sendable {
    case dismiss                                   // close the panel (most launch actions)
    case stay                                      // keep panel open (e.g. after a refresh)
    case pop                                       // pop one level, reload destination
    case popToRoot                                 // pop to the lane list (after archive/rename/delete)
    case enter(Lane)                              // reset to level 0 and enter this lane
    case pushInput(InputRequest)                   // push a single-field input level
    case pushItems(title: String, items: [any Item])  // push a pre-built level (menus, confirms)
}

protocol Item: Identifiable, Sendable {
    nonisolated var id: String { get }                        // stable, namespaced
    nonisolated var title: String { get }
    nonisolated var subtitle: String? { get }
    nonisolated var icon: IconToken { get }
    nonisolated var keywords: [String] { get }
    /// "Meta" actions (e.g. "Link Jira ticket…", "Manage lane…") that should
    /// rank *below* genuine content matches when searching, even if their
    /// title scores higher for the query.
    nonisolated var isSecondary: Bool { get }
    nonisolated var run: (@Sendable () async throws -> RunOutcome)? { get }
    nonisolated func children() async -> [any Item]
}

extension Item {
    var subtitle: String? { nil }
    var icon: IconToken { .generic }
    var keywords: [String] { [] }
    var isSecondary: Bool { false }
    var run: (@Sendable () async throws -> RunOutcome)? { nil }
    func children() async -> [any Item] { [] }
}

/// The one concrete type providers construct.
nonisolated struct BasicItem: Item {
    let id: String
    var title: String
    var subtitle: String? = nil
    var icon: IconToken = .generic
    var keywords: [String] = []
    var isSecondary: Bool = false
    var run: (@Sendable () async throws -> RunOutcome)? = nil
    var childrenProvider: @Sendable () async -> [any Item] = { [] }

    func children() async -> [any Item] { await childrenProvider() }
}
