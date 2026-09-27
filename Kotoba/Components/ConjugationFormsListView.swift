//
//  ConjugationFormsListView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import SwiftUI

struct ConjugationFormsListView: View {
    let forms: [ConjugationForm]
    var includesDictionary = false
    var columnCount = 1

    private var visibleForms: [ConjugationForm] {
        forms.filter { includesDictionary || $0.type != .dictionary }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: 28, alignment: .topLeading),
            count: max(1, columnCount)
        )
    }

    var body: some View {
        if !visibleForms.isEmpty {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(Array(visibleForms.enumerated()), id: \.offset) { _, form in
                    HStack(alignment: .top, spacing: 10) {
                        Text(form.type.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(form.surface)
                                .font(.body.weight(.medium))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(form.reading)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
