//
//  Item.swift
//  Lanes
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
    case enterWithNotice(Lane, notice: String)     // enter this lane and surface a message (e.g. a clone that finished with warnings)
    case pushInput(InputRequest)                   // push a single-field input level
    case pushItems(title: String, items: [any Item])  // push a pre-built level (menus, confirms)
}

protocol Item: Identifiable, Sendable {
    nonisolated var id: String { get }                        // stable, namespaced
    nonisolated var title: String { get }
    nonisolated var subtitle: String? { get }
    nonisolated var icon: IconToken { get }
    nonisolated var keywords: [String] { get }
    /// "Meta" actions (e.g. "Link ticket…", "Manage lane…") that should
    /// rank *below* genuine content matches when searching, even if their
    /// title scores higher for the query.
    nonisolated var isSecondary: Bool { get }
    /// Key used to order sibling items within a section (numeric-aware). Defaults
    /// to the title; script items set it to their `<order>---…` filename so the
    /// user's explicit ordering wins over alphabetical.
    nonisolated var sortKey: String { get }
    nonisolated var run: (@Sendable () async throws -> RunOutcome)? { get }
    nonisolated func children() async -> [any Item]
    /// For a container: when the user searches inside it and nothing matches,
    /// build a fallback action from the query (e.g. "Clone repo…" turns an
    /// unmatched query — a pasted clone URL — into a clone). nil = no fallback.
    nonisolated var queryFallback: (@Sendable (String) -> (any Item)?)? { get }
}

extension Item {
    var subtitle: String? { nil }
    var icon: IconToken { .generic }
    var keywords: [String] { [] }
    var isSecondary: Bool { false }
    var sortKey: String { title }
    var run: (@Sendable () async throws -> RunOutcome)? { nil }
    func children() async -> [any Item] { [] }
    var queryFallback: (@Sendable (String) -> (any Item)?)? { nil }
}

/// The one concrete type providers construct.
nonisolated struct BasicItem: Item {
    let id: String
    var title: String
    var subtitle: String? = nil
    var icon: IconToken = .generic
    var keywords: [String] = []
    var isSecondary: Bool = false
    /// Explicit sort key; falls back to `title` when nil.
    var sortValue: String? = nil
    var run: (@Sendable () async throws -> RunOutcome)? = nil
    var childrenProvider: @Sendable () async -> [any Item] = { [] }
    var queryFallback: (@Sendable (String) -> (any Item)?)? = nil

    var sortKey: String { sortValue ?? title }
    func children() async -> [any Item] { await childrenProvider() }
}
