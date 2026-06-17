//
//  FuzzyMatcher.swift
//  lane
//
//  Case-insensitive subsequence matching that scores contiguous runs and
//  word-boundary hits higher. Pure Swift, no dependency.
//

import Foundation

nonisolated enum FuzzyMatcher {
    private static let separators: Set<Character> = [" ", "/", "-", "_", ".", ":", "›"]

    /// Score `query` against `text`. Returns nil when `query` is not a
    /// subsequence of `text`. Higher is better.
    static func score(_ query: String, _ text: String) -> Double? {
        if query.isEmpty { return 0 }
        let q = Array(query.lowercased())
        let t = Array(text.lowercased())
        guard !t.isEmpty else { return nil }

        var qi = 0
        var total = 0.0
        var prevMatch = -2
        for ti in t.indices {
            guard qi < q.count, t[ti] == q[qi] else { continue }
            var s = 1.0
            if ti == prevMatch + 1 { s += 3.0 }                 // contiguous run
            if ti == 0 || separators.contains(t[ti - 1]) { s += 2.0 }  // word boundary
            total += s
            prevMatch = ti
            qi += 1
        }
        guard qi == q.count else { return nil }
        // Slight preference for denser (shorter) matches.
        return total - Double(t.count) * 0.01
    }

    /// Best score across an item's title (weighted) and keywords.
    static func score(query: String, title: String, keywords: [String] = []) -> Double? {
        if query.isEmpty { return 0 }
        var best: Double?
        if let s = score(query, title) {
            best = s + 1.0   // title weighted above keywords
        }
        for kw in keywords {
            if let s = score(query, kw) {
                best = max(best ?? -.greatestFiniteMagnitude, s)
            }
        }
        return best
    }
}
