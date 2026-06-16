//
//  StudySummaryView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftUI

struct StudySummaryView: View {
    let summary: StudySessionViewModel.Summary

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("今日学习完成")
                    .font(.title2.weight(.semibold))

                Text("辛苦了，今天的队列已经清空。")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                SummaryMetric(title: "完成卡片", value: summary.reviewedCount)
                SummaryMetric(title: "新词", value: summary.newWordCount)
                SummaryMetric(title: "遗忘", value: summary.lapseCount)
            }
            .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
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

#Preview {
    StudySummaryView(summary: .init(reviewedCount: 20, newWordCount: 8, lapseCount: 2))
        .frame(width: 620, height: 420)
}
