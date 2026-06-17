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
    /// extension, strip a leading ordering prefix ("10-deploy.sh" → "deploy"),
    /// and turn -/_ into spaces.
    static func title(for url: URL) -> String {
        // Remove the icon token first — it can contain dots, so it must go
        // before deletingPathExtension (which would otherwise mangle it).
        var name = url.lastPathComponent
            .replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        name = (name as NSString).deletingPathExtension
        name = name.replacingOccurrences(of: "^[0-9]+[-_ ]+", with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? url.lastPathComponent : trimmed
    }

    /// The SF Symbol name from a `[symbol]` token in the filename, e.g.
    /// `deploy[bolt.fill].sh` → "bolt.fill". Nil when there's no token.
    static func iconSymbol(for url: URL) -> String? {
        let name = url.lastPathComponent
        guard let r = name.range(of: "\\[[^\\]]+\\]", options: .regularExpression) else { return nil }
        let trimmed = name[r].dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The icon for a script: its `[symbol]` token if present, else the default
    /// scroll glyph. (Validity of a custom symbol is checked at render time.)
    static func icon(for url: URL) -> IconToken {
        iconSymbol(for: url).map(IconToken.custom) ?? .script
    }

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
        return BasicItem(
            id: id,
            title: Self.title(for: scriptURL),
            icon: Self.icon(for: scriptURL),
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
