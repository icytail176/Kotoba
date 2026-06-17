//
//  VocabularyImportResultView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftData
import SwiftUI

struct VocabularyImportResultView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var conjugationStats: ConjugationStats?
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

                if let wordBookName = result.wordBookName {
                    Text("目标词书：\(wordBookName)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
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

            if let conjugationStats {
                VStack(alignment: .leading, spacing: 10) {
                    Text("活用数据")
                        .font(.headline)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            ResultCell(title: "可能需要", value: conjugationStats.possibleCount)
                            ResultCell(title: "本地已处理", value: conjugationStats.localRuleCount)
                        }

                        GridRow {
                            ResultCell(title: "待补全", value: conjugationStats.pendingCount)
                            ResultCell(title: "需要检查", value: conjugationStats.needsReviewCount)
                        }
                    }
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
        .task(id: result.wordBookID) {
            loadConjugationStats()
        }
    }

    private func loadConjugationStats() {
        guard let wordBookID = result.wordBookID else {
            conjugationStats = nil
            return
        }

        do {
            let books = try modelContext.fetch(FetchDescriptor<WordBook>())
            guard let wordBook = books.first(where: { $0.id == wordBookID }) else {
                conjugationStats = nil
                return
            }

            conjugationStats = try ConjugationStatsService().stats(for: wordBook, in: modelContext)
        } catch {
            conjugationStats = nil
        }
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
            ignoredErrorCount: 3,
            wordBookID: UUID(),
            wordBookName: "N3 常用词"
        ),
        onDone: {}
    )
}
