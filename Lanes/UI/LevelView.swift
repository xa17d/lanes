//
//  LevelView.swift
//  Lanes
//
//  Scrollable list of rows for the current level, with loading shimmer and
//  empty states. Keeps the selection scrolled into view.
//

import SwiftUI

struct LevelView: View {
    @ObservedObject var model: LaneModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let rows = model.rows
        Group {
            if model.isInputMode {
                inputHint
            } else if rows.isEmpty {
                if isLoading {
                    shimmer
                } else {
                    emptyState
                }
            } else {
                list(rows)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var isLoading: Bool {
        model.currentLevel?.isLoading ?? false
    }

    private func list(_ rows: [DisplayRow]) -> some View {
        // Identity is the row's stable id for both ForEach diffing and
        // scrollTo. (Adding a separate positional .id(index) here fights the
        // ForEach identity and leaves ghost / wrong-level rows.)
        let selectedID = rows.indices.contains(model.selection) ? rows[model.selection].id : nil
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        RowView(row: row, isSelected: row.id == selectedID)
                            .onTapGesture {
                                if let idx = rows.firstIndex(where: { $0.id == row.id }) {
                                    model.selection = idx
                                    model.activateSelected()
                                }
                            }
                    }
                }
                .padding(.vertical, Tokens.Space.xs)
            }
            .frame(height: listHeight(rowCount: rows.count))
            .onChange(of: model.selection) { _, newValue in
                guard rows.indices.contains(newValue) else { return }
                let id = rows[newValue].id
                if reduceMotion {
                    proxy.scrollTo(id, anchor: .center)
                } else {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private func listHeight(rowCount: Int) -> CGFloat {
        min(CGFloat(rowCount) * Tokens.Size.rowHeight + Tokens.Space.xs * 2,
            Tokens.Size.panelMaxHeight)
    }

    private var shimmer: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: Tokens.Space.m) {
                    RoundedRectangle(cornerRadius: 4).frame(width: 22, height: 16)
                    RoundedRectangle(cornerRadius: 4).frame(width: 180, height: 12)
                    Spacer()
                }
                .padding(.horizontal, Tokens.Space.l)
                .frame(height: Tokens.Size.rowHeight)
                .foregroundStyle(.quaternary)
                .redacted(reason: .placeholder)
            }
        }
    }

    private var inputHint: some View {
        VStack(spacing: Tokens.Space.s) {
            Image(systemName: "return")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(model.currentInputRequest?.title ?? "")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var emptyState: some View {
        VStack(spacing: Tokens.Space.s) {
            Image(systemName: emptyIcon)
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyIcon: String {
        model.stack.isEmpty ? "folder.badge.plus" : "tray"
    }

    private var emptyMessage: String {
        if !model.query.isEmpty {
            return "No matches for “\(model.query)”."
        }
        if model.stack.isEmpty {
            if model.library.root == nil {
                return "Choose a root folder in Settings (⌘,) to get started."
            }
            return "No lanes yet. Press ⌘N to create one."
        }
        return "Nothing here yet.\nLink a ticket or drop a repo into this folder."
    }
}
