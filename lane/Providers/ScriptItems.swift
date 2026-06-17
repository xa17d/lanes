//
//  ScriptItems.swift
//  lane
//
//  Custom user actions backed by executable files under the root's
//  `.lanes/config/script-items/`. Lane-level scripts run with the lane dir as
//  cwd; `repository/` scripts run once per discovered repo with the repo dir as
//  cwd. Scripts run silently — a nonzero exit surfaces stderr as an error toast.
//

import Foundation

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

    /// Filename → display title: strip a `[sf.symbol]` icon token, drop the
    /// Filenames follow a fixed three-field format separated by `---`:
    ///
    ///     <order>---<name>---<icon>.<ext>
    ///
    /// - `order` is a sort key (e.g. `10`), stripped from the display name.
    /// - `name` is shown verbatim (ordinary dashes/spaces are kept).
    /// - `icon` is an SF Symbol name (e.g. `bolt.fill`), used for the icon.
    ///
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
        // Tolerate `---` inside the name by joining the middle fields back.
        let name = parts[1..<(parts.count - 1)].joined(separator: "---")
            .trimmingCharacters(in: .whitespaces)
        let iconName = parts[parts.count - 1].trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? url.lastPathComponent : name,
                iconName.isEmpty ? .script : .custom(iconName))
    }

    static func title(for url: URL) -> String { parse(url).title }
    static func icon(for url: URL) -> IconToken { parse(url).icon }

    // MARK: - Items

    /// Lane-level actions from `<root>/.lanes/config/script-items`.
    func laneItems(root: URL, lane: Lane) -> [any Item] {
        let env = Self.laneEnv(for: lane)
        return Self.executableFiles(in: LaneFS.scriptItemsDir(in: root)).map { url in
            item(id: "script:\(url.path)", scriptURL: url, cwd: lane.url, env: env)
        }
    }

    /// Per-repository actions, run in `repoURL`. `scripts` is the already-read
    /// listing of `<root>/.lanes/config/script-items/repository` (read once and
    /// reused across repos).
    func repoItems(scripts: [URL], repoURL: URL, lane: Lane) -> [any Item] {
        var env = Self.laneEnv(for: lane)
        env["REPO_DIR"] = repoURL.path
        env["REPO_NAME"] = repoURL.lastPathComponent
        return scripts.map { url in
            item(id: "repo:\(repoURL.path):script:\(url.path)", scriptURL: url, cwd: repoURL, env: env)
        }
    }

    // MARK: - Internals

    private static func laneEnv(for lane: Lane) -> [String: String] {
        ["LANE_DIR": lane.url.path, "LANE_NAME": lane.name, "LANE_ID": lane.id.uuidString]
    }

    private func item(id: String, scriptURL: URL, cwd: URL, env: [String: String]) -> any Item {
        let shell = self.shell
        let path = scriptURL.path
        let parsed = Self.parse(scriptURL)
        return BasicItem(
            id: id,
            title: parsed.title,
            icon: parsed.icon,
            keywords: ["script", "run", scriptURL.lastPathComponent],
            run: {
                // Silent: exec the file directly so its shebang chooses the
                // interpreter; a nonzero exit throws ShellError (stderr → toast).
                try shell.run(path, [], cwd: cwd, env: env)
                return .dismiss
            }
        )
    }
}
