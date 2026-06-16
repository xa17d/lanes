//
//  RootView.swift
//  lane
//
//  The launcher shell: search field, breadcrumb, level list, footer, and a
//  transient toast. Keyboard handling lives in the panel (NSEvent monitor) and
//  is routed into LaneModel.
//

import SwiftUI

struct RootView: View {
    @ObservedObject var model: LaneModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().opacity(0.4)
            Breadcrumb(labels: model.breadcrumb)
            LevelView(model: model)
            Footer(hint: hint)
        }
        .frame(width: Tokens.Size.panelWidth)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous))
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(state: toast)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.toast)
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: Tokens.Space.m) {
            Image(systemName: model.isInputMode ? "pencil" : "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            TextField(fieldPrompt, text: model.isInputMode ? $model.inputText : $model.query)
                .textFieldStyle(.plain)
                .font(Tokens.Font.search)
                .focused($searchFocused)
        }
        .padding(.horizontal, Tokens.Space.l)
        .frame(height: Tokens.Size.searchHeight)
    }

    private var fieldPrompt: String {
        if let request = model.currentInputRequest { return request.placeholder }
        if model.stack.isEmpty { return "Search tracks…" }
        return "Search \(model.currentTrack?.name ?? "")…"
    }

    private var hint: String {
        if model.isInputMode {
            return "↵ confirm · esc cancel"
        }
        if model.stack.isEmpty {
            return "↑↓ navigate · ↵ open · → manage · ⌘N new · esc close"
        }
        return "↑↓ navigate · ↵ open · → drill in · esc back"
    }
}
