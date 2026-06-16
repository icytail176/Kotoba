//
//  StudyStatisticsCalculator.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation

struct StudyLogSnapshot: Equatable, Hashable, Sendable {
    let id: UUID
    let wordID: UUID?
    let reviewedAt: Date
    let rating: ReviewRating
    let previousState: LearningState
    let nextState: LearningState
}

struct StudyWordSnapshot: Equatable, Hashable, Sendable {
    let id: UUID
    let expression: String
    let reading: String
    let meaningChinese: String
    let jlptLevel: String
    let isArchived: Bool
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
    let lapseCount: Int
}

struct JLPTStudyProgress: Identifiable, Equatable, Sendable {
    var id: String { level }

    let level: String
    let learnedCount: Int
    let totalCount: Int

    var progress: Double {
        guard totalCount > 0 else {
            return 0
        }

        return Double(learnedCount) / Double(totalCount)
    }
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
    let todayLapseCount: Int
    let totalLearnedWordCount: Int
    let totalReviewCount: Int
    let currentStreakDays: Int
    let recentDailyActivity: [DailyStudyActivity]
    let jlptProgress: [JLPTStudyProgress]
    let topLapsedWords: [LapsedWordSummary]

    var hasData: Bool {
        totalReviewCount > 0
    }
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
        let learnedWordIDs = Set(logs.compactMap(\.wordID))

        return StudyStatistics(
            todayNewWordCount: newWordCount(from: todayLogs),
            todayReviewCount: todayLogs.filter { $0.previousState != .new }.count,
            todayLapseCount: todayLogs.filter(isLapse).count,
            totalLearnedWordCount: learnedWordIDs.count,
            totalReviewCount: logs.count,
            currentStreakDays: currentStreakDays(from: logs, calendar: calendar, now: now),
            recentDailyActivity: recentDailyActivity(from: logs, calendar: calendar, now: now),
            jlptProgress: jlptProgress(from: input.words, learnedWordIDs: learnedWordIDs),
            topLapsedWords: topLapsedWords(from: logs, words: input.words)
        )
    }

    nonisolated private func uniqueLogs(_ logs: [StudyLogSnapshot]) -> [StudyLogSnapshot] {
        var seenIDs = Set<UUID>()
        var uniqueLogs: [StudyLogSnapshot] = []

        for log in logs where seenIDs.insert(log.id).inserted {
            uniqueLogs.append(log)
        }

        return uniqueLogs
    }

    nonisolated private func recentDailyActivity(
        from logs: [StudyLogSnapshot],
        calendar: Calendar,
        now: Date
    ) -> [DailyStudyActivity] {
        let groupedLogs = Dictionary(grouping: logs) { log in
            calendar.startOfDay(for: log.reviewedAt)
        }
        let today = calendar.startOfDay(for: now)

        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }

            let dayLogs = groupedLogs[calendar.startOfDay(for: day)] ?? []
            return DailyStudyActivity(
                day: day,
                totalCount: dayLogs.count,
                newWordCount: newWordCount(from: dayLogs),
                reviewCount: dayLogs.filter { $0.previousState != .new }.count,
                lapseCount: dayLogs.filter(isLapse).count
            )
        }
    }

    nonisolated func currentStreakDays(
        from logs: [StudyLogSnapshot],
        calendar: Calendar,
        now: Date
    ) -> Int {
        let studyDays = Set(logs.map { calendar.startOfDay(for: $0.reviewedAt) })
        var streak = 0
        var cursor = calendar.startOfDay(for: now)

        while studyDays.contains(cursor) {
            streak += 1

            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }

            cursor = calendar.startOfDay(for: previousDay)
        }

        return streak
    }

    nonisolated private func newWordCount(from logs: [StudyLogSnapshot]) -> Int {
        Set(logs.compactMap { log in
            log.previousState == .new ? log.wordID : nil
        }).count
    }

    nonisolated private func jlptProgress(
        from words: [StudyWordSnapshot],
        learnedWordIDs: Set<UUID>
    ) -> [JLPTStudyProgress] {
        let activeWords = words.filter { !$0.isArchived }
        let wordsByLevel = Dictionary(grouping: activeWords) { word in
            normalizedJLPTLevel(word.jlptLevel)
        }

        return wordsByLevel.map { level, words in
            JLPTStudyProgress(
                level: level,
                learnedCount: words.filter { learnedWordIDs.contains($0.id) }.count,
                totalCount: words.count
            )
        }
        .sorted { lhs, rhs in
            let lhsOrder = jlptSortOrder(lhs.level)
            let rhsOrder = jlptSortOrder(rhs.level)

            if lhsOrder == rhsOrder {
                return lhs.level < rhs.level
            }

            return lhsOrder < rhsOrder
        }
    }

    nonisolated private func topLapsedWords(
        from logs: [StudyLogSnapshot],
        words: [StudyWordSnapshot]
    ) -> [LapsedWordSummary] {
        let wordByID = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
        let lapsedLogsByWordID = Dictionary(grouping: logs.filter(isLapse).compactMap(\.wordID)) { $0 }

        return lapsedLogsByWordID.compactMap { wordID, wordIDs in
            guard let word = wordByID[wordID] else {
                return nil
            }

            return LapsedWordSummary(
                id: wordID,
                expression: word.expression,
                reading: word.reading,
                meaningChinese: word.meaningChinese,
                lapseCount: wordIDs.count
            )
        }
        .sorted {
            if $0.lapseCount == $1.lapseCount {
                return $0.expression < $1.expression
            }

            return $0.lapseCount > $1.lapseCount
        }
        .prefix(10)
        .map { $0 }
    }

    nonisolated private func isLapse(_ log: StudyLogSnapshot) -> Bool {
        guard log.rating == .again else {
            return false
        }

        return log.previousState == .review || log.previousState == .relearning
    }

    nonisolated private func normalizedJLPTLevel(_ rawValue: String) -> String {
        let level = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return level.isEmpty ? "未标注" : level
    }

    nonisolated private func jlptSortOrder(_ level: String) -> Int {
        switch level {
        case "N5":
            return 0
        case "N4":
            return 1
        case "N3":
            return 2
        case "N2":
            return 3
        case "N1":
            return 4
        case "未标注":
            return 5
        default:
            return 6
        }
    }
}
