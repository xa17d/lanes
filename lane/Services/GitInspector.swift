//
//  GitInspector.swift
//  lane
//
//  Repo discovery + branch/remote inspection via git.
//

import Foundation

nonisolated struct GitRemote: Sendable, Equatable {
    let host: String
    let owner: String   // may include a subgroup path for GitLab
    let slug: String

    var webBase: URL { URL(string: "https://\(host)/\(owner)/\(slug)")! }

    /// Parse the common remote URL forms. Returns nil if unrecognized.
    ///   git@github.com:owner/repo.git
    ///   https://github.com/owner/repo(.git)
    ///   ssh://git@host[:port]/owner/repo.git
    static func parse(_ raw: String) -> GitRemote? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.hasSuffix(".git") { s.removeLast(4) }

        // scp-like syntax: [user@]host:owner/repo
        if !s.contains("://"), let colon = s.firstIndex(of: ":") {
            let beforeColon = String(s[s.startIndex..<colon])
            let host = beforeColon.contains("@") ? String(beforeColon.split(separator: "@").last!) : beforeColon
            let path = String(s[s.index(after: colon)...])
            if let remote = fromHostPath(host: host, path: path) { return remote }
        }

        // URL syntax with a scheme.
        if let comps = URLComponents(string: s), let host = comps.host {
            return fromHostPath(host: host, path: comps.path)
        }
        return nil
    }

    private static func fromHostPath(host: String, path: String) -> GitRemote? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, !host.isEmpty else { return nil }
        let slug = parts.last!
        let owner = parts.dropLast().joined(separator: "/")
        return GitRemote(host: host, owner: owner, slug: slug)
    }
}

nonisolated struct GitInspector: Sendable {
    let shell: Shell
    private let gitPath = "/usr/bin/git"

    /// Depth-limited walk; a directory containing `.git` is a repo. Skips dot
    /// folders (incl. `.lane`/`.git`) and does not descend into a found repo.
    func discoverRepos(in root: URL, maxDepth: Int = 4) -> [URL] {
        let fm = FileManager.default
        var repos: [URL] = []

        func walk(_ dir: URL, _ depth: Int) {
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                repos.append(dir)
                return   // don't descend into a repo
            }
            guard depth < maxDepth else { return }
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            for entry in entries where !entry.lastPathComponent.hasPrefix(".") {
                if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    walk(entry, depth + 1)
                }
            }
        }

        walk(root, 0)
        return repos.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func branch(of repo: URL) -> String? {
        guard let out = try? shell.run(gitPath, ["-C", repo.path, "rev-parse", "--abbrev-ref", "HEAD"]) else {
            return nil
        }
        let name = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "HEAD" {
            // Detached: show the short SHA.
            if let sha = try? shell.run(gitPath, ["-C", repo.path, "rev-parse", "--short", "HEAD"]) {
                let short = sha.trimmingCharacters(in: .whitespacesAndNewlines)
                return short.isEmpty ? nil : short
            }
        }
        return name.isEmpty ? nil : name
    }

    func remote(of repo: URL) -> GitRemote? {
        guard let out = try? shell.run(gitPath, ["-C", repo.path, "remote", "get-url", "origin"]) else {
            return nil
        }
        return GitRemote.parse(out.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
