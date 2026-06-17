//
//  StatusBadge.swift
//  lane
//
//  A lane's description may embed a status badge with the syntax
//  `{{color:text}}` (e.g. "{{green:Ready to ship}}"). The first such marker
//  becomes a colored badge on the lane row; all markers are stripped from the
//  displayed (and searched) description body. Pure/Foundation-only so it can be
//  unit-tested directly.
//

import Foundation

nonisolated enum StatusColor: String, Sendable, CaseIterable {
    case gray, blue, green, yellow, orange, red, purple, pink
}

nonisolated struct StatusBadge: Sendable, Equatable, Hashable {
    let color: StatusColor
    let text: String

    // `{{ color : text }}` — color/text trimmed; an unknown color falls back to
    // gray; the text may be empty (renders as a bare colored dot).
    private static let pattern = "\\{\\{\\s*([^:{}]*?)\\s*:\\s*([^{}]*?)\\s*\\}\\}"

    /// Split a raw description into its status badge (first marker) and the body
    /// text with every marker removed and whitespace tidied.
    static func parse(from raw: String?) -> (badge: StatusBadge?, body: String) {
        guard let raw, !raw.isEmpty, let regex = try? NSRegularExpression(pattern: pattern) else {
            return (nil, raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        }
        let ns = raw as NSString
        let full = NSRange(location: 0, length: ns.length)

        var badge: StatusBadge?
        if let m = regex.firstMatch(in: raw, range: full) {
            let colorStr = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces).lowercased()
            let text = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            badge = StatusBadge(color: StatusColor(rawValue: colorStr) ?? .gray, text: text)
        }

        let stripped = regex.stringByReplacingMatches(in: raw, range: full, withTemplate: "")
        let body = stripped
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (badge, body)
    }

    /// Text a query should match against: the body plus the badge label.
    static func searchText(from raw: String?) -> String {
        let parsed = parse(from: raw)
        return [parsed.body, parsed.badge?.text]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
