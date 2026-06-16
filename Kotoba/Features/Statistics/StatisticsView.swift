//
//  StatisticsView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftUI
import SwiftData

struct StatisticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @StateObject private var viewModel = StatisticsViewModel()

    var body: some View {
        PageScaffold(title: "学习统计", subtitle: "了解学习进度、复习完成情况和词汇积累。") {
            content
        }
        .task {
            loadStatistics()
        }
        .alert(
            "统计加载失败",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button("好") {
                viewModel.errorMessage = nil
            }
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
            StatisticsDashboard(statistics: statistics)
        } else {
            EmptyStateView(
                systemImage: "chart.bar.xaxis",
                title: "还没有学习记录",
                message: "开始复习后，这里会展示完成数量、连续学习天数和复习趋势。"
            )
        }
    }

    private func loadStatistics() {
        var userCalendar = calendar
        userCalendar.timeZone = timeZone
        viewModel.load(context: modelContext, calendar: userCalendar)
    }
}

#Preview {
    StatisticsView()
        .modelContainer(PreviewModelContainer.make())
        .frame(width: 700, height: 500)
}

private struct StatisticsDashboard: View {
    let statistics: StudyStatistics

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                MetricGrid(statistics: statistics)

                StatisticsSection(title: "最近 7 天每日学习量") {
                    RecentActivityChart(activities: statistics.recentDailyActivity)
                }

                StatisticsSection(title: "JLPT 学习进度") {
                    JLPTProgressList(progressItems: statistics.jlptProgress)
                }

                StatisticsSection(title: "遗忘次数最多的 10 个单词") {
                    TopLapsedWordList(words: statistics.topLapsedWords)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MetricGrid: View {
    let statistics: StudyStatistics

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            MetricCard(title: "今日新学", value: statistics.todayNewWordCount, systemImage: "sparkle")
            MetricCard(title: "今日复习", value: statistics.todayReviewCount, systemImage: "arrow.clockwise")
            MetricCard(title: "今日遗忘", value: statistics.todayLapseCount, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
            MetricCard(title: "累计学习词数", value: statistics.totalLearnedWordCount, systemImage: "books.vertical")
            MetricCard(title: "累计复习次数", value: statistics.totalReviewCount, systemImage: "checkmark.circle")
            MetricCard(title: "连续学习天数", value: statistics.currentStreakDays, systemImage: "flame")
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(value)")
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .monospacedDigit()

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatisticsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecentActivityChart: View {
    let activities: [DailyStudyActivity]

    private var maxCount: Int {
        max(1, activities.map(\.totalCount).max() ?? 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(activities) { activity in
                DailyBar(activity: activity, maxCount: maxCount)
            }
        }
        .frame(height: 190)
    }
}

private struct DailyBar: View {
    let activity: DailyStudyActivity
    let maxCount: Int

    var body: some View {
        GeometryReader { proxy in
            let labelHeight: CGFloat = 46
            let maxBarHeight = max(20, proxy.size.height - labelHeight)
            let normalizedHeight = CGFloat(activity.totalCount) / CGFloat(maxCount) * maxBarHeight
            let barHeight = activity.totalCount == 0 ? 4 : max(8, normalizedHeight)

            VStack(spacing: 6) {
                Spacer(minLength: 0)

                Text("\(activity.totalCount)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                RoundedRectangle(cornerRadius: 4)
                    .fill(activity.totalCount == 0 ? Color.secondary.opacity(0.18) : Color.accentColor)
                    .frame(height: barHeight)

                VStack(spacing: 2) {
                    Text(activity.day.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "zh-Hans"))))
                    Text(activity.day.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(height: 34)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 42, maxWidth: .infinity)
        .help("新学 \(activity.newWordCount)，复习 \(activity.reviewCount)，遗忘 \(activity.lapseCount)")
    }
}

private struct JLPTProgressList: View {
    let progressItems: [JLPTStudyProgress]

    var body: some View {
        if progressItems.isEmpty {
            Text("暂无可统计的 JLPT 等级数据")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 10) {
                ForEach(progressItems) { item in
                    HStack(spacing: 12) {
                        Text(item.level)
                            .font(.callout.weight(.semibold))
                            .frame(width: 52, alignment: .leading)

                        ProgressView(value: item.progress)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: .infinity)

                        Text("\(item.learnedCount) / \(item.totalCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                    }
                }
            }
        }
    }
}

private struct TopLapsedWordList: View {
    let words: [LapsedWordSummary]

    var body: some View {
        if words.isEmpty {
            Text("还没有遗忘记录")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(word.expression)
                                .font(.body.weight(.medium))

                            lapsedWordDetailText(for: word)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 12)

                        Text("\(word.lapseCount) 次")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)

                    if index < words.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func lapsedWordDetailText(for word: LapsedWordSummary) -> Text {
        let reading = word.reading.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = word.meaningChinese.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (reading.isEmpty, meaning.isEmpty) {
        case (true, true):
            return Text("无补充信息")
        case (false, true):
            return Text(reading)
        case (true, false):
            return Text(meaning)
        case (false, false):
            return Text("\(reading) · \(meaning)")
        }
    }
}
