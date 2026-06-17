//
//  Toast.swift
//  lane
//
//  Transient bottom banner for action results and errors.
//

import SwiftUI

struct ToastView: View {
    let state: ToastState

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: state.kind == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(state.kind == .error ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
            Text(state.message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, Tokens.Space.m)
        .padding(.vertical, Tokens.Space.s)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(radius: 6, y: 2)
        .padding(.bottom, Tokens.Space.l)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
