//
//  StudySummaryView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftUI

struct StudySummaryView: View {
    let summary: StudySessionViewModel.Summary
    let onReturnHome: () -> Void

    init(summary: StudySessionViewModel.Summary, onReturnHome: @escaping () -> Void = {}) {
        self.summary = summary
        self.onReturnHome = onReturnHome
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                VStack(spacing: 8) {
                    Text("本组学习完成")
                        .font(.title2.weight(.semibold))

                    Text("\(summary.reviewedCount) 个词")
                        .font(.title.weight(.semibold))
                        .monospacedDigit()

                    Text("辛苦了，这组学习已经完成。")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    SummaryMetric(title: "忘记", value: summary.forgottenCount)
                    SummaryMetric(title: "模糊", value: summary.fuzzyCount)
                    SummaryMetric(title: "认识", value: summary.knownCount)
                    SummaryMetric(title: "熟练", value: summary.masteredCount)
                }
                .frame(maxWidth: 520)

                if summary.expressionSpelling.totalCount > 0 {
                    spellingMetrics(title: "第一轮 · 单词拼写", summary: summary.expressionSpelling, includesHint: true)
                        .frame(maxWidth: 760)
                }

                if summary.readingSpelling.totalCount > 0 {
                    spellingMetrics(title: "第二轮 · 假名拼写", summary: summary.readingSpelling, includesHint: false)
                        .frame(maxWidth: 760)
                }

                if !summary.wordResults.isEmpty {
                    wordResultsSection
                        .frame(maxWidth: 760)
                }

                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }

            Divider()
            HStack {
                Spacer()
                Button("返回首页", action: onReturnHome)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)
        }
    }

    private var wordResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本组单词")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(summary.wordResults) { result in
                    WordResultRow(result: result)
                }
            }
        }
    }

    private func spellingMetrics(
        title: String,
        summary: SpellingSessionViewModel.RoundSummary,
        includesHint: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                SummaryMetric(title: "需要拼写", value: summary.totalCount)
                SummaryMetric(title: "一次通过", value: summary.firstAttemptCorrectCount)
                SummaryMetric(title: "重练通过", value: summary.retryCorrectCount)
                if includesHint {
                    SummaryMetric(title: "其中使用提示", value: summary.usedHintCount)
                }
            }
        }
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.title.weight(.semibold))
                .monospacedDigit()

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct WordResultRow: View {
    let result: StudySessionViewModel.WordSessionResult

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                DetailLine(title: "卡片评价", value: result.cardRatingTitle)
                if result.isMastered {
                    DetailLine(title: "状态", value: "已移出学习")
                } else {
                    DetailLine(title: "单词拼写", value: expressionSpellingDescription)
                    DetailLine(title: "假名拼写", value: readingSpellingDescription)
                    LabeledContent("下次复习") {
                        Text(NextReviewDateFormatter.string(for: result.nextReviewAt))
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.expression)
                        .font(.body.weight(.semibold))
                    Text("\(result.reading) · \(result.meaningChinese)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(result.cardRatingTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(result.cardRating == .again ? .orange : .green)
                    Text(result.isMastered ? "已移出学习" : expressionSpellingDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private var expressionSpellingDescription: String {
        guard result.expressionRequiresSpelling else { return "已跳过" }
        if result.expressionPassedFirstTry { return "一次通过" }
        if result.expressionUsedHint { return "使用提示后重练通过" }
        return "重练 \(result.expressionRequeueCount) 次后通过"
    }

    private var readingSpellingDescription: String {
        guard result.readingRequiresSpelling else { return "不适用" }
        if result.readingPassedFirstTry { return "一次通过" }
        return "重练 \(result.readingRequeueCount) 次后通过"
    }
}

private struct DetailLine: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

#Preview {
    StudySummaryView(summary: .init(reviewedCount: 20, newWordCount: 8, lapseCount: 2))
        .frame(width: 620, height: 420)
}
