//
//  TicketProvider.swift
//  Lanes
//
//  Section 0. One item per linked ticket (focus-or-open in Chrome) plus a
//  trailing "Link ticket…" action. No ticket-tracker auth in v1.
//

import Foundation

nonisolated struct TicketLink: Codable, Sendable {
    let id: UUID
    let key: String
    let urlOverride: URL?
}

nonisolated struct TicketProvider: LaneProvider {
    let section = 0
    var displayName: String { "Tickets" }

    /// Per-lane store key. Kept as the legacy "jira" value so tickets linked
    /// before the rename to generic "ticket" vocabulary still load.
    private static let storeKey = "jira"

    func items(for lane: Lane, store: LaneStore, services: Services) async -> [any Item] {
        let links = store.value([TicketLink].self, Self.storeKey) ?? []
        let chrome = services.chrome
        let baseURL = services.ticketBaseURL

        var items: [any Item] = links.map { link in
            let key = link.key
            let override = link.urlOverride
            return BasicItem(
                id: "ticket:\(key)",
                title: key,
                icon: .ticket,
                keywords: ["ticket"],
                run: {
                    let linkURL = override ?? baseURL()?.appendingPathComponent(key)
                    guard let linkURL else {
                        throw InputError(message: "Set a ticket base URL in Settings (⌘,) first.")
                    }
                    try chrome.focusOrOpen(urlContaining: key, fallback: linkURL)
                    return .dismiss
                }
            )
        }

        items.append(BasicItem(
            id: "ticket:add",
            title: "Link ticket…",
            icon: .add,
            keywords: ["new", "link", "ticket"],
            isSecondary: true,   // rank below the actual linked tickets
            run: { .pushInput(Self.linkRequest(store: store)) }
        ))
        return items
    }

    private static func linkRequest(store: LaneStore) -> InputRequest {
        InputRequest(title: "Link ticket", placeholder: "PROJ-123 or paste a URL") { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let match = trimmed.firstMatch(of: /[A-Z][A-Z0-9]+-\d+/) else {
                throw InputError(message: "Enter a ticket key like PROJ-123.")
            }
            let key = String(match.output)
            var override: URL?
            if trimmed.lowercased().hasPrefix("http") { override = URL(string: trimmed) }
            var links = store.value([TicketLink].self, storeKey) ?? []
            links.append(TicketLink(id: UUID(), key: key, urlOverride: override))
            try store.setValue(links, storeKey)
            return .pop
        }
    }
}
