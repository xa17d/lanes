//
//  RowView.swift
//  lane
//
//  A single list row. Signature element: a 2pt accent leading rail on the
//  selected row — a literal "lane".
//

import SwiftUI

struct RowView: View {
    let row: DisplayRow
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            Image(systemName: row.icon.symbol)
                .font(.system(size: 15))
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                titleLine
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(Tokens.Font.mono)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Tokens.Space.s)

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
        .font(Tokens.Font.title)
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
