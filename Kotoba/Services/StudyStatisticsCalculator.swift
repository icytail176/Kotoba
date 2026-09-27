//
//  StudyStatisticsCalculator.swift
//  Kotoba
//

import Foundation

struct StudyLogSnapshot: Equatable, Hashable, Sendable {
    let id: UUID
    let wordID: UUID?
    let reviewedAt: Date
    let rating: ReviewRating
    let previousState: LearningState
}

struct StudyWordSnapshot: Equatable, Hashable, Sendable {
    let id: UUID
    let expression: String
    let reading: String
    let meaningChinese: String
}

struct StudyStatisticsInput: Equatable, Sendable {
    let logs: [StudyLogSnapshot]
    let words: [StudyWordSnapshot]
}

struct DailyStudyActivity: Identifiable, Equatable, Sendable {
    var id: Date { day }

    let day: Date
    let totalCount: Int
    let newWordCount: Int
    let reviewCount: Int
}

struct LapsedWordSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let expression: String
    let reading: String
    let meaningChinese: String
    let lapseCount: Int
}

struct StudyStatistics: Equatable, Sendable {
    let todayNewWordCount: Int
    let todayReviewCount: Int
    let totalLearnedWordCount: Int
    let totalReviewCount: Int
    let currentStreakDays: Int
    let recentDailyActivity: [DailyStudyActivity]
    let topLapsedWords: [LapsedWordSummary]

    var hasData: Bool { totalReviewCount > 0 }
}

struct StudyStatisticsCalculator: Sendable {
    nonisolated init() {}

    nonisolated func calculate(
        input: StudyStatisticsInput,
        calendar: Calendar,
        now: Date
    ) -> StudyStatistics {
        let logs = uniqueLogs(input.logs)
        let todayLogs = logs.filter { calendar.isDate($0.reviewedAt, inSameDayAs: now) }

        return StudyStatistics(
            todayNewWordCount: newWordCount(from: todayLogs),
            todayReviewCount: todayLogs.filter { $0.previousState != .new }.count,
            totalLearnedWordCount: Set(logs.compactMap(\.wordID)).count,
            totalReviewCount: logs.count,
            currentStreakDays: currentStreakDays(from: logs, calendar: calendar, now: now),
            recentDailyActivity: recentDailyActivity(from: logs, calendar: calendar, now: now),
            topLapsedWords: topLapsedWords(from: logs, words: input.words)
        )
    }

    nonisolated func currentStreakDays(
        from logs: [StudyLogSnapshot],
        calendar: Calendar,
        now: Date
    ) -> Int {
        let studyDays = Set(logs.map { calendar.startOfDay(for: $0.reviewedAt) })
        var cursor = calendar.startOfDay(for: now)
        var streak = 0

        while studyDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }
        return streak
    }

    nonisolated private func uniqueLogs(_ logs: [StudyLogSnapshot]) -> [StudyLogSnapshot] {
        var seen = Set<UUID>()
        return logs.filter { seen.insert($0.id).inserted }
    }

    nonisolated private func recentDailyActivity(
        from logs: [StudyLogSnapshot],
        calendar: Calendar,
        now: Date
    ) -> [DailyStudyActivity] {
        let grouped = Dictionary(grouping: logs) { calendar.startOfDay(for: $0.reviewedAt) }
        let today = calendar.startOfDay(for: now)

        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let dayLogs = grouped[day] ?? []
            return DailyStudyActivity(
                day: day,
                totalCount: dayLogs.count,
                newWordCount: newWordCount(from: dayLogs),
                reviewCount: dayLogs.filter { $0.previousState != .new }.count
            )
        }
    }

    nonisolated private func newWordCount(from logs: [StudyLogSnapshot]) -> Int {
        Set(logs.compactMap { $0.previousState == .new ? $0.wordID : nil }).count
    }

    nonisolated private func topLapsedWords(
        from logs: [StudyLogSnapshot],
        words: [StudyWordSnapshot]
    ) -> [LapsedWordSummary] {
        let wordsByID = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
        let lapseWordIDs = logs.compactMap { log -> UUID? in
            guard log.rating == .again,
                  log.previousState == .review || log.previousState == .relearning else { return nil }
            return log.wordID
        }

        let groupedWordIDs = Dictionary(grouping: lapseWordIDs, by: { $0 })
        let summaries: [LapsedWordSummary] = groupedWordIDs.compactMap { wordID, occurrences in
            guard let word = wordsByID[wordID] else { return nil }
            return LapsedWordSummary(
                id: wordID,
                expression: word.expression,
                reading: word.reading,
                meaningChinese: word.meaningChinese,
                lapseCount: occurrences.count
            )
        }
        let sorted = summaries.sorted {
            $0.lapseCount == $1.lapseCount ? $0.expression < $1.expression : $0.lapseCount > $1.lapseCount
        }
        return Array(sorted.prefix(10))
    }
}
