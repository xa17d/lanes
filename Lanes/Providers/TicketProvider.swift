//
//  TicketProvider.swift
//  Lanes
//
//  Section 0. One item per linked ticket (focus-or-open in Chrome). The
//  "Link ticket…" action lives under "Manage lane…" (built by LaneActions) so
//  the lane's top level holds only the actual tickets. No ticket-tracker auth
//  in v1.
//

import Foundation

nonisolated struct TicketLink: Codable, Sendable {
    let id: UUID
    let key: String
    let urlOverride: URL?
}

/// A lane's tickets resolved for script consumption. `key`/`url` are the
/// primary (first) ticket for the common single-ticket case; `keys`/`urls` are
/// every linked ticket (primary first), index-aligned so line N of one matches
/// line N of the other.
nonisolated struct TicketEnv: Sendable {
    let key: String
    let url: String     // empty when there's no override and no base URL
    let keys: [String]  // all linked ticket keys, primary first
    let urls: [String]  // all linked ticket URLs (aligned with `keys`; "" when unresolvable)

    /// Separator for the list vars. Newline so a script can iterate them line by
    /// line (`while read`) or `paste` keys against URLs.
    static let listSeparator = "\n"

    /// The `TICKET_*` vars to layer onto a lane's base `scriptEnv`:
    /// `TICKET_KEY`/`TICKET_URL` (primary) plus `TICKET_KEYS`/`TICKET_URLS`
    /// (all of them, newline-separated).
    var vars: [String: String] {
        [
            "TICKET_KEY": key,
            "TICKET_URL": url,
            "TICKET_KEYS": keys.joined(separator: Self.listSeparator),
            "TICKET_URLS": urls.joined(separator: Self.listSeparator),
        ]
    }
}

nonisolated struct TicketProvider: LaneProvider {
    let section = 0
    var displayName: String { "Tickets" }

    private static let storeKey = "ticket"

    /// The lane's linked tickets resolved for script env vars, or nil when none
    /// is linked. Each URL mirrors the item's own logic: an explicit override,
    /// else the configured base URL joined with the key. The first link is the
    /// primary (`TICKET_KEY`/`TICKET_URL`); all of them feed the list vars.
    static func env(store: LaneStore, baseURL: @Sendable () -> URL?) -> TicketEnv? {
        let links = store.value([TicketLink].self, storeKey) ?? []
        guard let primary = links.first else { return nil }
        func resolve(_ link: TicketLink) -> String {
            (link.urlOverride ?? baseURL()?.appendingPathComponent(link.key))?.absoluteString ?? ""
        }
        return TicketEnv(key: primary.key, url: resolve(primary),
                         keys: links.map(\.key), urls: links.map(resolve))
    }

    /// Link `key` to the lane unless it's already linked (idempotent upsert by
    /// key, so re-running the `extract-ticket` hook never duplicates a ticket).
    /// Returns true when a new link was added.
    @discardableResult
    static func link(key: String, urlOverride: URL? = nil, store: LaneStore) throws -> Bool {
        var links = store.value([TicketLink].self, storeKey) ?? []
        guard !links.contains(where: { $0.key == key }) else { return false }
        links.append(TicketLink(id: UUID(), key: key, urlOverride: urlOverride))
        try store.setValue(links, storeKey)
        return true
    }

    func items(for lane: Lane, store: LaneStore, services: Services) async -> [any Item] {
        let links = store.value([TicketLink].self, Self.storeKey) ?? []
        let chrome = services.chrome
        let baseURL = services.ticketBaseURL

        return links.map { link in
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
    }

    /// The "Link ticket…" action. Composed into "Manage lane…" (see
    /// `LaneActions`) rather than shown at the lane's top level.
    static func linkTicketItem(store: LaneStore) -> any Item {
        BasicItem(
            id: "ticket:add",
            title: "Link ticket…",
            icon: .add,
            keywords: ["new", "link", "ticket"],
            isSecondary: true,
            run: { .pushInput(linkRequest(store: store)) }
        )
    }

    private static func linkRequest(store: LaneStore) -> InputRequest {
        InputRequest(title: "Link ticket", placeholder: "PROJ-123 or paste a URL") { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let match = trimmed.firstMatch(of: /[A-Z][A-Z0-9]+-\d+/) else {
                throw InputError(message: "Enter a ticket key like PROJ-123.")
            }
            let override = trimmed.lowercased().hasPrefix("http") ? URL(string: trimmed) : nil
            try link(key: String(match.output), urlOverride: override, store: store)
            return .pop
        }
    }
}
