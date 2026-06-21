//
//  ScriptItems.swift
//  Lanes
//
//  Custom user actions backed by executable files under the root's
//  `.lanes/config/script-items/`. Lane-level scripts run with the lane dir as
//  cwd; `repository/` scripts run once per discovered repo with the repo dir as
//  cwd. Scripts run silently — a nonzero exit surfaces stderr as an error toast.
//

import Foundation

/// One resolved custom action: `display` is the local filename (it drives the
/// order/title/icon and the item id), `exec` is the executable actually run —
/// the same file for a plain script, or a catalog target for a `.catalog`
/// pointer.
nonisolated struct EffectiveScript: Sendable {
    let display: URL
    let exec: URL
}

nonisolated struct ScriptItems: Sendable {
    let shell: Shell

    // MARK: - Enumeration

    /// Executable, non-hidden regular files directly inside `dir`, sorted by
    /// filename. Directories (e.g. the `repository` subfolder) and READMEs are
    /// skipped, so only runnable scripts become actions.
    static func executableFiles(in dir: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { url in
                let name = url.lastPathComponent
                if name.hasPrefix(".") || name.lowercased().hasPrefix("readme") { return false }
                let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                return isRegular && fm.isExecutableFile(atPath: url.path)
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// The effective actions in `dir`: plain executable files run as-is, plus
    /// `.catalog` pointer files resolved to their catalog target. Both are
    /// ordered by the *local* filename, so a pointer's `<order>---<icon>---<name>`
    /// filename drives its display exactly like a local script. Pointers whose
    /// catalog/item can't be resolved are dropped (they show nothing).
    static func effectiveScripts(in dir: URL, root: URL) -> [EffectiveScript] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [EffectiveScript] = []
        for url in entries {
            let name = url.lastPathComponent
            if name.hasPrefix(".") || name.lowercased().hasPrefix("readme") { continue }
            if Catalogs.isPointer(url) {
                if let target = Catalogs.resolvePointer(at: url, root: root) {
                    out.append(EffectiveScript(display: url, exec: target))
                }
                continue
            }
            let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if isRegular && fm.isExecutableFile(atPath: url.path) {
                out.append(EffectiveScript(display: url, exec: url))
            }
        }
        return out.sorted {
            $0.display.lastPathComponent.localizedStandardCompare($1.display.lastPathComponent) == .orderedAscending
        }
    }

    /// Filename → display title + icon. Filenames follow a fixed three-field
    /// format separated by `---`, with the extension always required:
    ///
    ///     <order>---<icon>---<name>.<ext>
    ///
    /// - `order` is a sort key (e.g. `10`), stripped from the display name.
    /// - `icon` is an SF Symbol name (e.g. `bolt.fill`), used for the icon.
    /// - `name` is shown verbatim (ordinary dashes/spaces are kept).
    ///
    /// `icon` sits before `name` (and the extension is mandatory) so a dotted
    /// SF Symbol name like `bolt.fill` can never be mistaken for the extension.
    /// The extension is removed first, then the base is split on `---`. A file
    /// that doesn't match (fewer than three fields) falls back to showing its
    /// whole base name with the default scroll icon.
    static func parse(_ url: URL) -> (title: String, icon: IconToken) {
        let base = (url.lastPathComponent as NSString).deletingPathExtension
        let parts = base.components(separatedBy: "---")
        guard parts.count >= 3 else {
            let fallback = base.trimmingCharacters(in: .whitespaces)
            return (fallback.isEmpty ? url.lastPathComponent : fallback, .script)
        }
        let iconName = parts[1].trimmingCharacters(in: .whitespaces)
        // Tolerate `---` inside the name by joining the trailing fields back.
        let name = parts[2...].joined(separator: "---")
            .trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? url.lastPathComponent : name,
                iconName.isEmpty ? .script : .custom(iconName))
    }

    static func title(for url: URL) -> String { parse(url).title }
    static func icon(for url: URL) -> IconToken { parse(url).icon }

    // MARK: - Items

    /// Lane-level actions from `<root>/.lanes/config/script`.
    func laneItems(root: URL, lane: Lane, ticket: TicketEnv?) -> [any Item] {
        let env = Self.laneEnv(for: lane, ticket: ticket)
        return Self.effectiveScripts(in: LaneFS.scriptDir(in: root), root: root).map { script in
            item(id: "script:\(script.display.path)", script: script, cwd: lane.url, env: env)
        }
    }

    /// Per-repository actions, run in `repoURL`. `scripts` is the already-read
    /// listing of `<root>/.lanes/config/script/repository` (read once and reused
    /// across repos).
    func repoItems(scripts: [EffectiveScript], repoURL: URL, lane: Lane, ticket: TicketEnv?) -> [any Item] {
        var env = Self.laneEnv(for: lane, ticket: ticket)
        env["REPO_DIR"] = repoURL.path
        env["REPO_NAME"] = repoURL.lastPathComponent
        return scripts.map { script in
            item(id: "repo:\(repoURL.path):script:\(script.display.path)", script: script, cwd: repoURL, env: env)
        }
    }

    // MARK: - Internals

    private static func laneEnv(for lane: Lane, ticket: TicketEnv?) -> [String: String] {
        var env = ["LANE_DIR": lane.url.path, "LANE_NAME": lane.name, "LANE_ID": lane.id.uuidString]
        if let ticket {
            env["TICKET_KEY"] = ticket.key
            env["TICKET_URL"] = ticket.url
        }
        return env
    }

    private func item(id: String, script: EffectiveScript, cwd: URL, env: [String: String]) -> any Item {
        let shell = self.shell
        let path = script.exec.path
        let parsed = Self.parse(script.display)
        return BasicItem(
            id: id,
            title: parsed.title,
            icon: parsed.icon,
            keywords: ["script", "run", script.display.lastPathComponent],
            run: {
                // Silent: exec the file directly so its shebang chooses the
                // interpreter; a nonzero exit throws ShellError (stderr → toast).
                try shell.run(path, [], cwd: cwd, env: env)
                return .dismiss
            }
        )
    }
}
