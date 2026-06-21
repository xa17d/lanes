//
//  SubtreeIndex.swift
//  Lanes
//
//  A flat, depth-first index of a level's items and their descendants, each
//  labeled with the breadcrumb path to reach it. Lets a non-empty query
//  surface a nested action from the top level (e.g. "service-api › Open PR").
//

import Foundation

nonisolated struct IndexedItem: Identifiable, Sendable {
    let item: any Item
    let breadcrumb: [String]   // ancestor titles, not including the item itself

    var id: String { item.id + "@" + breadcrumb.joined(separator: "›") }
}

nonisolated enum SubtreeIndex {
    /// Build a depth-first index from `items`, descending up to `maxDepth`
    /// levels and capping total entries to stay bounded.
    static func build(from items: [any Item], maxDepth: Int = 4, cap: Int = 2000) async -> [IndexedItem] {
        var out: [IndexedItem] = []

        func visit(_ items: [any Item], _ crumb: [String], _ depth: Int) async {
            for item in items {
                if out.count >= cap { return }
                out.append(IndexedItem(item: item, breadcrumb: crumb))
                guard depth < maxDepth else { continue }
                let kids = await item.children()
                if !kids.isEmpty {
                    await visit(kids, crumb + [item.title], depth + 1)
                }
            }
        }

        await visit(items, [], 0)
        return out
    }

    /// Filter + rank an index against a query, best match first.
    static func search(_ index: [IndexedItem], query: String) -> [IndexedItem] {
        guard !query.isEmpty else { return index }
        let scored = index.compactMap { entry -> (IndexedItem, Double)? in
            guard let s = FuzzyMatcher.score(query: query,
                                             title: entry.item.title,
                                             keywords: entry.item.keywords) else { return nil }
            return (entry, s)
        }
        // Primary (content) matches first, then secondary "meta" actions like
        // "Link Jira ticket…"; within each group, best score first.
        return scored.sorted { a, b in
            if a.0.item.isSecondary != b.0.item.isSecondary { return !a.0.item.isSecondary }
            return a.1 > b.1
        }.map(\.0)
    }
}
