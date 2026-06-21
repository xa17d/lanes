//
//  RowView.swift
//  Lanes
//
//  A single list row. Signature element: a 2pt accent leading rail on the
//  selected row — a literal "lane".
//

import SwiftUI
import AppKit

struct RowView: View {
    let row: DisplayRow
    let isSelected: Bool

    /// Custom (script-supplied) SF Symbol names may be invalid; fall back to the
    /// script glyph rather than rendering blank. Built-in tokens always resolve.
    private var symbolName: String {
        let name = row.icon.symbol
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
            ? name : IconToken.script.symbol
    }

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            Image(systemName: symbolName)
                .font(.system(size: 15))
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                titleLine
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(row.isLane ? Tokens.Font.subtitle : Tokens.Font.mono)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Tokens.Space.s)

            if let badge = row.badge {
                StatusBadgeView(badge: badge)
            }

            if row.isContainer {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, Tokens.Space.m)
        .frame(height: Tokens.Size.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectionBackground)
        .overlay(alignment: .leading) { accentRail }
        .contentShape(Rectangle())
    }

    private var titleLine: some View {
        HStack(spacing: 0) {
            if !row.pathLabels.isEmpty {
                Text(row.pathLabels.joined(separator: " › ") + " › ")
                    .foregroundStyle(.secondary)
            }
            Text(row.title)
                .foregroundStyle(.primary)
        }
        .font(row.isLane ? Tokens.Font.laneTitle : Tokens.Font.title)
        .lineLimit(1)
    }

    @ViewBuilder private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
                .padding(.horizontal, Tokens.Space.s)
        }
    }

    @ViewBuilder private var accentRail: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor)
                .frame(width: 2, height: 22)
                .padding(.leading, Tokens.Space.xs)
        }
    }
}

/// A colored status pill parsed from a lane's `{{badge:color:text}}` description
/// marker. An empty label renders as a bare colored dot.
///
/// Contrast: the badge sits on a translucent vibrancy backdrop (the desktop
/// shows through) that varies with the user's wallpaper and the system
/// appearance, so a single saturated system color used for both text and a
/// near-transparent fill reads poorly (pale yellow/green/pink especially).
/// Instead each token resolves to a `BadgeStyle` with a *deep, readable* text
/// color, a *soft tint* fill, and a hairline stroke that anchors the pill edge.
/// Both colors are appearance-aware (richer in light mode, brighter in dark).
struct StatusBadgeView: View {
    let badge: StatusBadge

    var body: some View {
        let style = Self.style(for: badge.color)
        Group {
            if badge.text.isEmpty {
                Circle().fill(style.text).frame(width: 8, height: 8)
            } else {
                Text(badge.text)
                    .font(Tokens.Font.badge)
                    .foregroundStyle(style.text)
                    .lineLimit(1)
                    .padding(.horizontal, Tokens.Space.s)
                    .padding(.vertical, 2)
                    .background(style.fill, in: Capsule())
                    .overlay(Capsule().strokeBorder(style.text.opacity(0.22), lineWidth: 0.5))
            }
        }
        .fixedSize()
    }

    /// Foreground (text/dot) and fill colors for a badge token.
    struct BadgeStyle {
        let text: Color
        let fill: Color
    }

    static func style(for status: StatusColor) -> BadgeStyle {
        let (light, dark) = Self.hues(for: status)
        let text = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? dark.nsColor : light.nsColor
        })
        // Fill is the same hue at low alpha; a touch stronger in dark mode where
        // the backdrop is darker. Kept subtle so the pill never looks heavy.
        let fill = Color(nsColor: NSColor(name: nil) { appearance in
            let base = appearance.isDark ? dark : light
            return base.nsColor.withAlphaComponent(appearance.isDark ? 0.26 : 0.20)
        })
        return BadgeStyle(text: text, fill: fill)
    }

    /// Per-token (light, dark) text hues. Light values are deep enough to read
    /// as small semibold text on the soft tint; dark values are brightened so
    /// they stay legible on a dark, translucent surface.
    private static func hues(for status: StatusColor) -> (light: RGB, dark: RGB) {
        switch status {
        case .gray:   return (RGB(0.36, 0.38, 0.40), RGB(0.72, 0.74, 0.77))
        case .blue:   return (RGB(0.10, 0.36, 0.80), RGB(0.51, 0.71, 1.00))
        case .green:  return (RGB(0.10, 0.46, 0.22), RGB(0.45, 0.83, 0.55))
        case .yellow: return (RGB(0.55, 0.42, 0.02), RGB(0.93, 0.79, 0.36))
        case .orange: return (RGB(0.66, 0.36, 0.04), RGB(0.99, 0.69, 0.36))
        case .red:    return (RGB(0.74, 0.18, 0.16), RGB(1.00, 0.55, 0.52))
        case .purple: return (RGB(0.46, 0.26, 0.74), RGB(0.78, 0.62, 1.00))
        case .pink:   return (RGB(0.76, 0.20, 0.46), RGB(1.00, 0.56, 0.76))
        }
    }
}

/// A plain sRGB triple, bridged to `NSColor` for dynamic (appearance-aware)
/// badge colors.
private struct RGB {
    let r, g, b: CGFloat
    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) { self.r = r; self.g = g; self.b = b }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}

private extension NSAppearance {
    /// True when the effective appearance is one of the dark variants.
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
