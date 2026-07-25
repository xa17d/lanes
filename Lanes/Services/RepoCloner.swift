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

    /// Clone `repo` into `lane`. Runs synchronously (blocks until git exits), so
    /// call it off the main actor; a nonzero exit throws with stderr for a toast.
    func clone(_ repo: KnownRepo, into lane: Lane, root: URL) throws {
        let dest = lane.url.appendingPathComponent(repo.name)
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            throw InputError(message: "“\(repo.name)” already exists in this lane.")
        }
        let env = [
            "LANE_DIR": lane.url.path,
            "LANE_NAME": lane.name,
            "LANE_ID": lane.id.uuidString,
            "REPO_URL": repo.url,
            "REPO_NAME": repo.name,
        ]
        if let handler = Self.handler(root: root) {
            try shell.run(handler.path, [], cwd: lane.url, env: env)
        } else {
            try shell.run(Self.gitPath, ["clone", "--", repo.url, repo.name], cwd: lane.url, env: env)
        }
    }

    /// The effective clone-repo handler: a `clone-repo.catalog` pointer wins over
    /// a local executable `clone-repo` file (delete the pointer to fall back);
    /// the resolved target must be an executable regular file. nil when neither
    /// is present/runnable, meaning the built-in `git clone` is used.
    static func handler(root: URL) -> URL? {
        let fm = FileManager.default
        let pointer = LaneFS.cloneScriptPointer(in: root)
        if fm.fileExists(atPath: pointer.path),
           let target = Catalogs.resolveExecutable(at: pointer, root: root) {
            return target
        }
        let local = LaneFS.cloneScript(in: root)
        let isRegular = (try? local.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
        return (isRegular && fm.isExecutableFile(atPath: local.path)) ? local : nil
    }
}
