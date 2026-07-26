//
//  ScriptFilename.swift
//  Lanes
//
//  The one parser for the custom-action filename format shared by script items,
//  catalog pointers, and the Settings editor:
//
//      <order>---<icon>---<name>.<ext>
//
//  The extension is stripped first, then the base is split on `---`, so a dotted
//  SF Symbol name (e.g. `bolt.fill`) in the icon field can never be mistaken for
//  the extension. Foundation-only and isolation-free so every layer (providers,
//  UI editor, the harness) parses filenames the same way.
//

import Foundation

nonisolated struct ScriptFilename: Sendable {
    /// Sort key from the first field; nil when absent or non-numeric.
    let order: Int?
    /// SF Symbol name from the second field; nil when absent or empty.
    let icon: String?
    /// Display name from the remaining fields (verbatim), never empty.
    let name: String

    /// Parse a filename in the `<order>---<icon>---<name>.<ext>` format. A name
    /// with fewer than three fields yields the whole (extension-stripped) base as
    /// `name`, with `order`/`icon` nil — callers apply their own defaults.
    static func parse(_ url: URL) -> ScriptFilename {
        let base = (url.lastPathComponent as NSString).deletingPathExtension
        let parts = base.components(separatedBy: "---")
        guard parts.count >= 3 else {
            let fallback = base.trimmingCharacters(in: .whitespaces)
            return ScriptFilename(order: nil, icon: nil,
                                  name: fallback.isEmpty ? url.lastPathComponent : fallback)
        }
        let order = Int(parts[0].trimmingCharacters(in: .whitespaces))
        let icon = parts[1].trimmingCharacters(in: .whitespaces)
        // Tolerate `---` inside the name by joining the trailing fields back.
        let name = parts[2...].joined(separator: "---").trimmingCharacters(in: .whitespaces)
        return ScriptFilename(order: order,
                              icon: icon.isEmpty ? nil : icon,
                              name: name.isEmpty ? url.lastPathComponent : name)
    }
}
