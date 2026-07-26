//
//  FileHelpers.swift
//  Lanes
//
//  Small filesystem predicates shared by every config-directory enumerator
//  (script items, catalog resolution, hooks, the clone handler, the editor).
//  Foundation-only and isolation-free so the model/service/provider layers and
//  the swiftc harness can all use them.
//

import Foundation

nonisolated extension URL {
    /// True when this is a regular file with the executable bit set — the
    /// predicate every "is this a runnable script?" check needs. A script/hook/
    /// clone-handler is exec'd directly (its shebang picks the interpreter), so a
    /// directory or a non-executable file must never qualify.
    var isExecutableRegularFile: Bool {
        let isRegular = (try? resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
        return isRegular && FileManager.default.isExecutableFile(atPath: path)
    }

    /// True for entries a config directory should ignore: dotfiles (belt-and-
    /// suspenders with `.skipsHiddenFiles`) and any `README*`. Used so only real
    /// config entries (scripts, item folders, pointers) become actions.
    var isDotfileOrReadme: Bool {
        let name = lastPathComponent
        return name.hasPrefix(".") || name.lowercased().hasPrefix("readme")
    }
}
