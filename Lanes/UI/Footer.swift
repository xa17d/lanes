//
//  Footer.swift
//  Lanes
//
//  Keyboard hint strip at the bottom of the panel.
//

import SwiftUI

struct Footer: View {
    let hint: String

    var body: some View {
        HStack {
            Text(hint)
                .font(Tokens.Font.footer)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, Tokens.Space.l)
        .frame(height: Tokens.Size.footerHeight)
        .background(.quaternary.opacity(0.25))
    }
}
