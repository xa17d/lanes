//
//  HostAdapter.swift
//  Lanes
//
//  URL builders for known git hosts. v1 builds URLs only — no gh/glab
//  dependency. PR/CI items only appear when a host is recognized.
//

import Foundation

nonisolated protocol HostAdapter: Sendable {
    func matches(_ r: GitRemote) -> Bool
    func prURL(_ r: GitRemote, branch: String) -> URL
    func ciURL(_ r: GitRemote, branch: String) -> URL
}

/// Percent-encode a branch for use in a query value (encodes `/` and `:`).
nonisolated func encodeBranch(_ branch: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return branch.addingPercentEncoding(withAllowedCharacters: allowed) ?? branch
}

nonisolated struct GitHubHost: HostAdapter {
    func matches(_ r: GitRemote) -> Bool {
        r.host == "github.com" || r.host.contains("github.")
    }
    func prURL(_ r: GitRemote, branch: String) -> URL {
        URL(string: "https://\(r.host)/\(r.owner)/\(r.slug)/pulls?q=is%3Apr+head%3A\(encodeBranch(branch))")!
    }
    func ciURL(_ r: GitRemote, branch: String) -> URL {
        URL(string: "https://\(r.host)/\(r.owner)/\(r.slug)/actions?query=branch%3A\(encodeBranch(branch))")!
    }
}

nonisolated struct GitLabHost: HostAdapter {
    func matches(_ r: GitRemote) -> Bool { r.host.contains("gitlab") }
    func prURL(_ r: GitRemote, branch: String) -> URL {
        URL(string: "https://\(r.host)/\(r.owner)/\(r.slug)/-/merge_requests?scope=all&state=opened&source_branch=\(encodeBranch(branch))")!
    }
    func ciURL(_ r: GitRemote, branch: String) -> URL {
        URL(string: "https://\(r.host)/\(r.owner)/\(r.slug)/-/pipelines?ref=\(encodeBranch(branch))")!
    }
}

nonisolated struct BitbucketHost: HostAdapter {
    func matches(_ r: GitRemote) -> Bool { r.host.contains("bitbucket") }
    func prURL(_ r: GitRemote, branch: String) -> URL {
        URL(string: "https://bitbucket.org/\(r.owner)/\(r.slug)/pull-requests/?query=\(encodeBranch(branch))")!
    }
    func ciURL(_ r: GitRemote, branch: String) -> URL {
        URL(string: "https://bitbucket.org/\(r.owner)/\(r.slug)/pipelines")!
    }
}

nonisolated struct HostResolver: Sendable {
    let adapters: [any HostAdapter]

    init(adapters: [any HostAdapter] = [GitHubHost(), GitLabHost(), BitbucketHost()]) {
        self.adapters = adapters
    }

    func adapter(for r: GitRemote) -> (any HostAdapter)? {
        adapters.first { $0.matches(r) }
    }
}
