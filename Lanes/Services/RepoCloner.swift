//
//  RepoCloner.swift
//  Lanes
//
//  Clones a known repo into a lane. Hybrid: if a `clone-repo` handler is
//  configured it delegates to that (so the user controls depth, submodules,
//  LFS, post-clone setup); otherwise it runs a plain `git clone`. Either way the
//  cwd is the lane dir and the destination is `<lane>/<name>`, and an existing
//  destination is a hard error (never overwrite).
//

import Foundation

nonisolated struct RepoCloner: Sendable {
    let shell: Shell
    private static let gitPath = "/usr/bin/git"

    nonisolated enum Outcome: Sendable {
        case cloned
        /// The clone command exited non-zero but still produced the repo (e.g.
        /// macOS checkout warnings for case/long-path conflicts, or a failing
        /// post-clone step). The repo is usable; `stderr` is the warning text.
        case clonedWithWarnings(String)
    }

    /// Clone `repo` into `<lane>/<repo.name>`. Runs synchronously (blocks until
    /// the clone exits), so call it off the main actor.
    ///
    /// A non-zero exit that **still produced the repo** is reported as
    /// `.clonedWithWarnings` rather than thrown — on macOS `git clone` commonly
    /// exits non-zero on checkout warnings while the repo is fully cloned, and
    /// the caller must still refresh the lane so the new repo shows. Only a
    /// clone that produced no repo (or a pre-existing destination) throws.
    func clone(_ repo: KnownRepo, into lane: Lane, root: URL) throws -> Outcome {
        let dest = lane.url.appendingPathComponent(repo.name)
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            throw InputError(message: "“\(repo.name)” already exists in this lane.")
        }
        let env = lane.scriptEnv.merging([
            "REPO_URL": repo.url,
            "REPO_NAME": repo.name,
        ]) { _, new in new }
        do {
            if let handler = Self.handler(root: root) {
                try shell.run(handler.path, [], cwd: lane.url, env: env)
            } else {
                try shell.run(Self.gitPath, ["clone", "--", repo.url, repo.name], cwd: lane.url, env: env)
            }
            return .cloned
        } catch let ShellError.nonzeroExit(status, stderr) {
            let created = FileManager.default.fileExists(
                atPath: dest.appendingPathComponent(".git").path)
            guard created else { throw ShellError.nonzeroExit(status: status, stderr: stderr) }
            return .clonedWithWarnings(stderr)
        }
    }

    /// The effective clone-repo handler: a `clone-repo.catalog` pointer wins over
    /// a local executable `clone-repo` file (delete the pointer to fall back);
    /// the resolved target must be an executable regular file. nil when neither
    /// is present/runnable, meaning the built-in `git clone` is used.
    static func handler(root: URL) -> URL? {
        Catalogs.resolveSingleton(
            localFile: LaneFS.cloneScript(in: root),
            pointer: LaneFS.cloneScriptPointer(in: root),
            root: root)
    }
}
