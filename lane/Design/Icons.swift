//
//  Icons.swift
//  lane
//
//  IconToken → SF Symbol mapping (§9). Providers reference semantic tokens,
//  never raw symbol names.
//

import Foundation

nonisolated enum IconToken: Sendable, Hashable {
    case folder          // lane folder / finder
    case jira
    case repo
    case pullRequest
    case ci
    case fork
    case editor
    case terminal
    case claude
    case code
    case add
    case archive
    case unarchive
    case rename
    case trash
    case open
    case reveal
    case manage
    case generic

    var symbol: String {
        switch self {
        case .folder:       return "folder"
        case .jira:         return "tag"
        case .repo:         return "chevron.left.forwardslash.chevron.right"
        case .pullRequest:  return "arrow.triangle.pull"
        case .ci:           return "checkmark.seal"
        case .fork:         return "arrow.triangle.branch"
        case .editor:       return "hammer"
        case .terminal:     return "terminal"
        case .claude:       return "sparkles"
        case .code:         return "chevron.left.slash.chevron.right"
        case .add:          return "plus"
        case .archive:      return "archivebox"
        case .unarchive:    return "tray.and.arrow.up"
        case .rename:       return "pencil"
        case .trash:        return "trash"
        case .open:         return "arrow.right.circle"
        case .reveal:       return "folder"
        case .manage:       return "gearshape"
        case .generic:      return "circle"
        }
    }
}
