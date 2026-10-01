//
//  StatisticsView.swift
//  Kotoba
//

import SwiftData
import SwiftUI

struct StatisticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @StateObject private var viewModel = StatisticsViewModel()

    var body: some View {
        PageScaffold(title: "学习统计", subtitle: "查看学习节奏与需要加强的单词。") {
            content
        }
        .task { loadStatistics() }
        .alert(
            "统计加载失败",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("好") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading, viewModel.statistics == nil {
            ProgressView("正在统计学习记录…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let statistics = viewModel.statistics, statistics.hasData {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Picker("统计范围", selection: rangeBinding) {
                        ForEach(StatisticsTimeRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                    metricGrid(statistics)
                    Text("熟练与拼写统计以正式评价记录为准；自动熟练仍计为“认识”，另在熟练明细中列出。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 20) {
                        LabeledContent("累计已学") {
                            Text("\(statistics.totalLearnedWordCount) 个词").monospacedDigit()
                        }
                        LabeledContent("连续学习") {
                            Text("\(statistics.currentStreakDays) 天").monospacedDigit()
                        }
                    }
                    .foregroundStyle(.secondary)
                    statisticsSection("\(statistics.selectedRange.title)学习活动") {
                        RecentStudyChart(activities: statistics.recentDailyActivity)
                    }
                    statisticsSection("评价分布") {
                        RatingDistributionChart(distribution: statistics.ratingDistribution)
                    }
                    statisticsSection("最难的 10 个单词") {
                        DifficultWordList(words: statistics.topLapsedWords)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyStateView(
                systemImage: "chart.bar.xaxis",
                title: "还没有学习记录",
                message: "完成一次学习后，这里会显示今日进度、连续学习天数和最近趋势。"
            )
        }
    }

    private func metricGrid(_ statistics: StudyStatistics) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            StatisticMetricCard(title: "正式评价", value: "\(statistics.periodFormalReviewCount)", systemImage: "checkmark.circle")
            StatisticMetricCard(title: "新学词数", value: "\(statistics.periodNewlyLearnedWordCount)", systemImage: "sparkles")
            StatisticMetricCard(
                title: masteryTitle(statistics),
                value: "\(statistics.periodManualMasteryCount + statistics.periodAutomaticMasteryCount)",
                systemImage: "bolt.circle"
            )
            StatisticMetricCard(
                title: spellingTitle(statistics.spellingFirstPassAccuracy),
                value: statistics.spellingFirstPassAccuracy.displayText,
                systemImage: "square.and.pencil"
            )
        }
    }

    private var rangeBinding: Binding<StatisticsTimeRange> {
        Binding(
            get: { viewModel.selectedRange },
            set: { viewModel.selectRange($0) }
        )
    }

    private func masteryTitle(_ statistics: StudyStatistics) -> String {
        "熟练（手动 \(statistics.periodManualMasteryCount) / 自动 \(statistics.periodAutomaticMasteryCount)）"
    }

    private func spellingTitle(_ accuracy: SpellingFirstPassAccuracy) -> String {
        guard accuracy.eligibleCount > 0 else { return "拼写首次通过率（暂无样本）" }
        return "拼写首次通过率（\(accuracy.passedCount)/\(accuracy.eligibleCount)）"
    }

    private func statisticsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadStatistics() {
        var userCalendar = calendar
        userCalendar.timeZone = timeZone
        viewModel.load(context: modelContext, calendar: userCalendar)
    }
}

private struct StatisticMetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.title2.monospacedDigit().weight(.semibold))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct RecentStudyChart: View {
    let activities: [DailyStudyActivity]

    private var maximum: Int { max(1, activities.map(\.totalCount).max() ?? 1) }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(activities) { activity in
                    VStack(spacing: 6) {
                        Text("\(activity.totalCount)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(activity.totalCount == 0 ? Color.secondary.opacity(0.16) : Color.accentColor)
                            .frame(height: activity.totalCount == 0 ? 4 : max(8, CGFloat(activity.totalCount) / CGFloat(maximum) * 105))
                        Text(activity.day.formatted(.dateTime.day().locale(Locale(identifier: "zh-Hans"))))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: activities.count > 7 ? 24 : 54)
                    .help("新学 \(activity.newWordCount)，复习 \(activity.reviewCount)")
                }
            }
            .frame(minWidth: 420, minHeight: 150, alignment: .bottomLeading)
        }
        .frame(height: 150, alignment: .bottom)
    }
}

private struct RatingDistributionChart: View {
    let distribution: RatingDistribution

    private var entries: [(String, Int, Color)] {
        [
            ("忘记", distribution.againCount, .red),
            ("模糊", distribution.hardCount, .orange),
            ("认识", distribution.goodCount, .green),
            ("熟练", distribution.masteredCount, .blue)
        ]
    }

    private var maximum: Int { max(1, entries.map(\.1).max() ?? 1) }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(entries, id: \.0) { entry in
                HStack(spacing: 10) {
                    Text(entry.0)
                        .frame(width: 42, alignment: .leading)
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(entry.2.opacity(entry.1 == 0 ? 0.16 : 0.72))
                            .frame(width: max(4, proxy.size.width * CGFloat(entry.1) / CGFloat(maximum)))
                    }
                    .frame(height: 12)
                    Text("\(entry.1)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DifficultWordList: View {
    let words: [LapsedWordSummary]

    var body: some View {
        if words.isEmpty {
            Text("目前没有需要特别加强的单词。")
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(word.expression).fontWeight(.medium)
                            Text([word.reading, word.meaningChinese].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("重学 \(word.lapseCount) 次")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 9)
                    if index < words.count - 1 { Divider() }
                }
            }
        }
    }
}

#Preview {
    StatisticsView()
        .modelContainer(PreviewModelContainer.make())
        .frame(width: 700, height: 500)
}
