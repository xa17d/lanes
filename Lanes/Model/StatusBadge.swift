//
//  StatusBadge.swift
//  Lanes
//
//  A lane's description may embed inline directives with the uniform syntax
//  `{{name:args}}`, parsed by `DescriptionMarkup`:
//
//    {{badge:<color>:<text>}}  — a colored status pill (text optional)
//    {{refresh:<duration>}}    — how often `update-lane-description` should be
//                                re-run (e.g. 30s, 30m, 2h, 1d, or bare seconds)
//
//  The first badge / first refresh wins; every directive is stripped from the
//  displayed (and searched) body. Pure/Foundation-only so it's unit-testable.
//

import Foundation

nonisolated enum StatusColor: String, Sendable, CaseIterable {
    case gray, blue, green, yellow, orange, red, purple, pink
}

nonisolated struct StatusBadge: Sendable, Equatable, Hashable {
    let color: StatusColor
    let text: String
}

nonisolated struct DescriptionMarkup: Sendable, Equatable {
    var badge: StatusBadge?
    var refresh: TimeInterval?   // seconds, from {{refresh:…}}
    var body: String

    // Any `{{ … }}` token; the inside is split into a directive name + args.
    private static let pattern = "\\{\\{\\s*([^{}]*?)\\s*\\}\\}"

    /// Parse a raw description into its directives (first badge / first refresh)
    /// and the body text with every directive removed and whitespace tidied.
    static func parse(from raw: String?) -> DescriptionMarkup {
        guard let raw, !raw.isEmpty, let regex = try? NSRegularExpression(pattern: pattern) else {
            return DescriptionMarkup(badge: nil, refresh: nil,
                                     body: raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        }
        let ns = raw as NSString
        let full = NSRange(location: 0, length: ns.length)

        var badge: StatusBadge?
        var refresh: TimeInterval?
        for m in regex.matches(in: raw, range: full) {
            let (name, args) = splitFirst(ns.substring(with: m.range(at: 1)), on: ":")
            switch name.trimmingCharacters(in: .whitespaces).lowercased() {
            case "badge" where badge == nil:
                let (colorStr, text) = splitFirst(args, on: ":")
                let color = StatusColor(rawValue: colorStr.trimmingCharacters(in: .whitespaces).lowercased()) ?? .gray
                badge = StatusBadge(color: color, text: text.trimmingCharacters(in: .whitespaces))
            case "refresh" where refresh == nil:
                refresh = duration(args)
            default:
                break   // unknown or duplicate directive: just stripped below
            }
        }

        let stripped = regex.stringByReplacingMatches(in: raw, range: full, withTemplate: "")
        let body = stripped
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return DescriptionMarkup(badge: badge, refresh: refresh, body: body)
    }

    /// Text a query should match against: the body plus the badge label.
    static func searchText(from raw: String?) -> String {
        let parsed = parse(from: raw)
        return [parsed.body, parsed.badge?.text]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Helpers

    /// Split `s` on its first `sep` into (before, after). The remainder keeps any
    /// further separators, so a badge's text may itself contain ':'.
    private static func splitFirst(_ s: String, on sep: Character) -> (String, String) {
        guard let i = s.firstIndex(of: sep) else { return (s, "") }
        return (String(s[..<i]), String(s[s.index(after: i)...]))
    }

    /// Parse "30s" / "30m" / "2h" / "1d" / bare seconds into a TimeInterval.
    /// Returns nil for malformed or non-positive values.
    static func duration(_ s: String) -> TimeInterval? {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        guard let unit = t.last else { return nil }
        let multiplier: Double
        let number: Substring
        switch unit {
        case "s": (multiplier, number) = (1, t.dropLast())
        case "m": (multiplier, number) = (60, t.dropLast())
        case "h": (multiplier, number) = (3600, t.dropLast())
        case "d": (multiplier, number) = (86400, t.dropLast())
        default:  (multiplier, number) = (1, t[...])   // bare number = seconds
        }
        guard let n = Double(number), n > 0 else { return nil }
        return n * multiplier
    }
}
