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
                    metricGrid(statistics)
                    statisticsSection("最近 7 天学习量") {
                        RecentStudyChart(activities: statistics.recentDailyActivity)
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
            StatisticMetricCard(title: "今日新学", value: statistics.todayNewWordCount, systemImage: "sparkles")
            StatisticMetricCard(title: "今日复习", value: statistics.todayReviewCount, systemImage: "arrow.clockwise")
            StatisticMetricCard(title: "累计已学", value: statistics.totalLearnedWordCount, systemImage: "books.vertical")
            StatisticMetricCard(title: "连续学习", value: statistics.currentStreakDays, suffix: "天", systemImage: "flame")
        }
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
    let value: Int
    var suffix = ""
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(value)\(suffix)")
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
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(activities) { activity in
                VStack(spacing: 6) {
                    Text("\(activity.totalCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(activity.totalCount == 0 ? Color.secondary.opacity(0.16) : Color.accentColor)
                        .frame(height: activity.totalCount == 0 ? 4 : max(8, CGFloat(activity.totalCount) / CGFloat(maximum) * 105))
                    Text(activity.day.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "zh-Hans"))))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .help("新学 \(activity.newWordCount)，复习 \(activity.reviewCount)")
            }
        }
        .frame(height: 150, alignment: .bottom)
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
