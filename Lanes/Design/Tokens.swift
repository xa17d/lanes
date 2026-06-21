//
//  Tokens.swift
//  Lanes
//
//  Spacing, sizing, and type tokens from the design spec (§9). Visual polish
//  and full usage land in Phase 9; these are the shared constants.
//

import SwiftUI

enum Tokens {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let row: CGFloat = 8
        static let panel: CGFloat = 16
    }

    enum Size {
        static let panelWidth: CGFloat = 720
        static let panelMaxHeight: CGFloat = 520
        static let rowHeight: CGFloat = 44
        static let searchHeight: CGFloat = 52
        static let footerHeight: CGFloat = 28
    }

    enum Font {
        static let title = SwiftUI.Font.system(size: 15, weight: .medium)
        static let laneTitle = SwiftUI.Font.system(size: 16, weight: .semibold)
        static let subtitle = SwiftUI.Font.system(size: 12)
        static let badge = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let search = SwiftUI.Font.system(size: 22)
        static let mono = SwiftUI.Font.system(size: 12, design: .monospaced)
        static let footer = SwiftUI.Font.system(size: 11)
        static let breadcrumb = SwiftUI.Font.system(size: 12)
    }
}
