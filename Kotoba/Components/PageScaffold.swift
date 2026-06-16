//
//  PageScaffold.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftUI

struct PageScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 18)

            Divider()

            content
        }
        .navigationTitle(title)
    }
}
