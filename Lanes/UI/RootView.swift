//
//  RootView.swift
//  Lanes
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
            laneSummary
            keepAwakeBanner
            catalogUpdateBanner
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
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Tokens.Space.l)
        .frame(height: Tokens.Size.searchHeight)
        .animation(.easeInOut(duration: 0.15), value: model.isRefreshing)
    }

    /// The active lane's one-line description, shown under the breadcrumb so
    /// you can tell at a glance which lane you're in. A `{{badge:color:text}}`
    /// directive is rendered as a colored badge rather than shown raw.
    @ViewBuilder private var laneSummary: some View {
        let parsed = DescriptionMarkup.parse(from: model.currentLane?.summary)
        if parsed.badge != nil || !parsed.body.isEmpty {
            HStack(spacing: Tokens.Space.s) {
                if !parsed.body.isEmpty {
                    Text(parsed.body)
                        .font(Tokens.Font.subtitle.italic())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: Tokens.Space.s)
                if let badge = parsed.badge {
                    StatusBadgeView(badge: badge)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Tokens.Space.l)
            .padding(.bottom, Tokens.Space.s)
        }
    }

    /// While keep-awake is active, an informational banner with a quick "Turn
    /// Off". Shown at any depth (it reflects a global state). ⌘K also toggles it.
    @ViewBuilder private var keepAwakeBanner: some View {
        if model.keepAwakeActive {
            HStack(spacing: Tokens.Space.s) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keeping your Mac awake")
                        .font(Tokens.Font.subtitle)
                    Text("System sleep is paused while agents run · ⌘K to toggle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Tokens.Space.s)
                Button("Turn Off") { model.toggleKeepAwake() }
                    .buttonStyle(.plain)
                    .font(Tokens.Font.subtitle)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Tokens.Space.l)
            .padding(.vertical, Tokens.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.10))
        }
    }

    /// At the lane list, a tappable banner when a subscribed catalog has an
    /// update waiting — opens Settings on the Catalogs pane.
    @ViewBuilder private var catalogUpdateBanner: some View {
        if model.stack.isEmpty && model.catalogUpdatesAvailable {
            Button { model.onOpenCatalogSettings() } label: {
                HStack(spacing: Tokens.Space.s) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Catalog updates available")
                        .font(Tokens.Font.subtitle)
                    Spacer(minLength: Tokens.Space.s)
                    Text("Review")
                        .font(Tokens.Font.subtitle)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Tokens.Space.l)
                .padding(.vertical, Tokens.Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.orange.opacity(0.10))
        }
    }

    private var fieldPrompt: String {
        if let request = model.currentInputRequest { return request.placeholder }
        if model.stack.isEmpty { return "Search lanes…" }
        return "Search \(model.currentLane?.name ?? "")…"
    }

    private var hint: String {
        if model.isInputMode {
            return "↵ confirm · esc cancel"
        }
        if model.stack.isEmpty {
            let archived = model.includeArchived ? "⌘⇧A archived (shown)" : "⌘⇧A archived"
            return "↑↓ navigate · ↵ open · ⌘N new · \(archived) · ⌘R refresh · ⌘K awake · esc close"
        }
        return "↑↓ navigate · ↵ open · ⌘R refresh · ⌘K awake · esc back · ⌘W close"
    }
}
