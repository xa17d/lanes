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
                if url.isDotfileOrReadme { return false }
                return url.isExecutableRegularFile
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
            if url.isDotfileOrReadme { continue }
            if Catalogs.isPointer(url) {
                if let target = Catalogs.resolveExecutable(at: url, root: root) {
                    out.append(EffectiveScript(display: url, exec: target))
                }
                continue
            }
            if url.isExecutableRegularFile {
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
    /// A file that doesn't match (fewer than three fields) falls back to showing
    /// its whole base name with the default scroll icon. Parsing itself lives in
    /// `ScriptFilename`; here we map the icon field to an `IconToken`.
    static func parse(_ url: URL) -> (title: String, icon: IconToken) {
        let parsed = ScriptFilename.parse(url)
        return (parsed.name, parsed.icon.map(IconToken.custom) ?? .script)
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
        lane.scriptEnv.merging(ticket?.vars ?? [:]) { _, new in new }
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
            // Order by the local `<order>---…` filename so the editor's ordering
            // is honored instead of falling back to alphabetical title sort.
            sortValue: script.display.lastPathComponent,
            run: {
                // Silent: exec the file directly so its shebang chooses the
                // interpreter; a nonzero exit throws ShellError (stderr → toast).
                try shell.run(path, [], cwd: cwd, env: env)
                return .dismiss
            }
        )
    }
}
