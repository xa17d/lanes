//
//  Breadcrumb.swift
//  lane
//
//  Lane › Item › … path above the list. Truncates head-first.
//

import SwiftUI

struct Breadcrumb: View {
    let labels: [String]

    var body: some View {
        if labels.isEmpty {
            EmptyView()
        } else {
            Text(labels.joined(separator: "  ›  "))
                .font(Tokens.Font.breadcrumb)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Tokens.Space.l)
                .padding(.vertical, Tokens.Space.s)
        }
    }
}
