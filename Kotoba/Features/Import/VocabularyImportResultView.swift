//
//  VocabularyImportResultView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftUI

struct VocabularyImportResultView: View {
    let result: VocabularyImportResult
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("导入完成")
                    .font(.title2.weight(.semibold))

                Text("已完成本次 CSV 导入，错误行已跳过。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    ResultCell(title: "新增", value: result.insertedCount)
                    ResultCell(title: "更新", value: result.updatedCount)
                }

                GridRow {
                    ResultCell(title: "跳过重复", value: result.skippedDuplicateCount)
                    ResultCell(title: "忽略错误行", value: result.ignoredErrorCount)
                }
            }

            HStack {
                Spacer()

                Button("完成", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }
}

private struct ResultCell: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value.formatted())
                .font(.title2.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }
}

#Preview {
    VocabularyImportResultView(
        result: VocabularyImportResult(
            insertedCount: 8,
            updatedCount: 2,
            skippedDuplicateCount: 1,
            ignoredErrorCount: 3
        ),
        onDone: {}
    )
}
