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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // Show motion: cross-fade always; subtle scale unless Reduce Motion.
        .scaleEffect(reduceMotion ? 1 : (model.panelAppeared ? 1 : 0.98))
        .opacity(model.panelAppeared ? 1 : 0)
        .animation(.easeOut(duration: 0.14), value: model.panelAppeared)
        .onAppear { searchFocused = true }
        .onChange(of: model.panelAppeared) { _, appeared in
            if appeared { searchFocused = true }
        }
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
            let base = "↑↓ navigate · ↵ open · → manage · ⌘N new · ⌘⇧A archived"
            return model.includeArchived ? base + " (shown)" : base
        }
        return "↑↓ navigate · ↵ open · → drill in · esc back"
    }
}
