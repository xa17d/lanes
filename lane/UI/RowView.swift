//
//  RowView.swift
//  lane
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

/// A colored status pill parsed from a lane's `{{color:text}}` description
/// marker. An empty label renders as a bare colored dot.
struct StatusBadgeView: View {
    let badge: StatusBadge

    var body: some View {
        let color = Self.color(for: badge.color)
        Group {
            if badge.text.isEmpty {
                Circle().fill(color).frame(width: 8, height: 8)
            } else {
                Text(badge.text)
                    .font(Tokens.Font.badge)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .padding(.horizontal, Tokens.Space.s)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.16), in: Capsule())
            }
        }
        .fixedSize()
    }

    static func color(for status: StatusColor) -> Color {
        switch status {
        case .gray:   return .gray
        case .blue:   return .blue
        case .green:  return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red:    return .red
        case .purple: return .purple
        case .pink:   return .pink
        }
    }
}
