//
//  JiraProvider.swift
//  lane
//
//  Section 0. One item per linked Jira ticket (focus-or-open in Chrome) plus a
//  trailing "Link Jira ticket…" action. No Jira auth in v1.
//

import Foundation

nonisolated struct JiraLink: Codable, Sendable {
    let id: UUID
    let key: String
    let urlOverride: URL?
}

nonisolated struct JiraProvider: LaneProvider {
    let section = 0
    var displayName: String { "Jira" }

    func items(for lane: Lane, store: LaneStore, services: Services) async -> [any Item] {
        let links = store.value([JiraLink].self, "jira") ?? []
        let chrome = services.chrome
        let baseURL = services.jiraBaseURL

        var items: [any Item] = links.map { link in
            let key = link.key
            let override = link.urlOverride
            return BasicItem(
                id: "jira:\(key)",
                title: key,
                icon: .jira,
                keywords: ["jira", "ticket"],
                run: {
                    let linkURL = override ?? baseURL()?.appendingPathComponent(key)
                    guard let linkURL else {
                        throw InputError(message: "Set a Jira base URL in Settings (⌘,) first.")
                    }
                    try chrome.focusOrOpen(urlContaining: key, fallback: linkURL)
                    return .dismiss
                }
            )
        }

        items.append(BasicItem(
            id: "jira:add",
            title: "Link Jira ticket…",
            icon: .add,
            keywords: ["new", "link", "jira"],
            isSecondary: true,   // rank below the actual linked tickets
            run: { .pushInput(Self.linkRequest(store: store)) }
        ))
        return items
    }

    private static func linkRequest(store: LaneStore) -> InputRequest {
        InputRequest(title: "Link Jira ticket", placeholder: "PROJ-123 or paste a URL") { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let match = trimmed.firstMatch(of: /[A-Z][A-Z0-9]+-\d+/) else {
                throw InputError(message: "Enter a ticket key like PROJ-123.")
            }
            let key = String(match.output)
            var override: URL?
            if trimmed.lowercased().hasPrefix("http") { override = URL(string: trimmed) }
            var links = store.value([JiraLink].self, "jira") ?? []
            links.append(JiraLink(id: UUID(), key: key, urlOverride: override))
            try store.setValue(links, "jira")
            return .pop
        }
    }
}
