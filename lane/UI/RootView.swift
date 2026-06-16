//
//  RootView.swift
//  lane
//
//  The launcher shell: search field on top, content below. Phase 2 wires the
//  chrome (autofocus, sizing, material); navigation + data arrive in Phase 5.
//

import SwiftUI

struct RootView: View {
    let onClose: () -> Void

    @State private var query: String = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().opacity(0.4)
            content
            footer
        }
        .frame(width: Tokens.Size.panelWidth)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous))
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: Tokens.Space.m) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            TextField("Search tracks…", text: $query)
                .textFieldStyle(.plain)
                .font(Tokens.Font.search)
                .focused($searchFocused)
        }
        .padding(.horizontal, Tokens.Space.l)
        .frame(height: Tokens.Size.searchHeight)
    }

    private var content: some View {
        VStack(spacing: Tokens.Space.s) {
            Image(systemName: "road.lanes")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            Text("Launcher shell")
                .font(.headline)
            Text("Navigation and tracks arrive in a later phase.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
    }

    private var footer: some View {
        HStack {
            Text("↑↓ navigate · ↵ open · esc close")
                .font(Tokens.Font.footer)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, Tokens.Space.l)
        .frame(height: Tokens.Size.footerHeight)
        .background(.quaternary.opacity(0.3))
    }
}
