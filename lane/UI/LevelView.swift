//
//  LevelView.swift
//  lane
//
//  Scrollable list of rows for the current level, with loading shimmer and
//  empty states. Keeps the selection scrolled into view.
//

import SwiftUI

struct LevelView: View {
    @ObservedObject var model: LaneModel

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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        RowView(row: row, isSelected: index == model.selection)
                            .id(index)
                            .onTapGesture {
                                model.selection = index
                                model.activateSelected()
                            }
                    }
                }
                .padding(.vertical, Tokens.Space.xs)
            }
            .frame(maxHeight: Tokens.Size.panelMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: model.selection) { _, newValue in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
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
            return "No tracks yet. Press ⌘N to create one."
        }
        return "Nothing here yet.\nLink a Jira ticket or drop a repo into this folder."
    }
}
