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
    let nextState: LearningState
    let hasSpellingDiagnostics: Bool
    let readingWrongCount: Int
    let spellingWrongCount: Int
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

enum StatisticsTimeRange: Int, CaseIterable, Identifiable, Sendable {
    case sevenDays = 7
    case thirtyDays = 30

    var id: Int { rawValue }
    var title: String { "最近 \(rawValue) 天" }
}

struct RatingDistribution: Equatable, Sendable {
    let againCount: Int
    let hardCount: Int
    let goodCount: Int
    let masteredCount: Int

    var totalCount: Int { againCount + hardCount + goodCount + masteredCount }
}

struct SpellingFirstPassAccuracy: Equatable, Sendable {
    let passedCount: Int
    let eligibleCount: Int

    var percentage: Int? {
        guard eligibleCount > 0 else { return nil }
        return Int((Double(passedCount) / Double(eligibleCount) * 100).rounded())
    }

    var displayText: String {
        guard let percentage else { return "—" }
        return "\(percentage)%"
    }
}

struct StudyStatistics: Equatable, Sendable {
    let todayNewWordCount: Int
    let todayReviewCount: Int
    let totalLearnedWordCount: Int
    let totalReviewCount: Int
    let currentStreakDays: Int
    let selectedRange: StatisticsTimeRange
    let periodFormalReviewCount: Int
    let periodNewlyLearnedWordCount: Int
    let periodManualMasteryCount: Int
    let periodAutomaticMasteryCount: Int
    let ratingDistribution: RatingDistribution
    let spellingFirstPassAccuracy: SpellingFirstPassAccuracy
    let recentDailyActivity: [DailyStudyActivity]
    let topLapsedWords: [LapsedWordSummary]

    var hasData: Bool { totalReviewCount > 0 }
}

struct StudyStatisticsCalculator: Sendable {
    nonisolated init() {}

    nonisolated func calculate(
        input: StudyStatisticsInput,
        calendar: Calendar,
        now: Date,
        range: StatisticsTimeRange = .sevenDays
    ) -> StudyStatistics {
        let logs = uniqueLogs(input.logs)
        let todayLogs = logs.filter { calendar.isDate($0.reviewedAt, inSameDayAs: now) }
        let periodLogs = logsInRange(logs, range: range, calendar: calendar, now: now)

        return StudyStatistics(
            todayNewWordCount: newWordCount(from: todayLogs),
            todayReviewCount: todayLogs.filter { $0.previousState != .new }.count,
            totalLearnedWordCount: Set(logs.compactMap(\.wordID)).count,
            totalReviewCount: logs.count,
            currentStreakDays: currentStreakDays(from: logs, calendar: calendar, now: now),
            selectedRange: range,
            periodFormalReviewCount: periodLogs.count,
            periodNewlyLearnedWordCount: newlyLearnedWordCount(
                allLogs: logs,
                periodLogs: periodLogs
            ),
            periodManualMasteryCount: periodLogs.filter {
                $0.rating == .easy && $0.nextState == .suspended
            }.count,
            periodAutomaticMasteryCount: periodLogs.filter {
                $0.rating == .good && $0.nextState == .suspended
            }.count,
            ratingDistribution: ratingDistribution(from: periodLogs),
            spellingFirstPassAccuracy: spellingFirstPassAccuracy(
                from: periodLogs,
                words: input.words
            ),
            recentDailyActivity: recentDailyActivity(
                from: periodLogs,
                dayCount: range.rawValue,
                calendar: calendar,
                now: now
            ),
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
        dayCount: Int,
        calendar: Calendar,
        now: Date
    ) -> [DailyStudyActivity] {
        let grouped = Dictionary(grouping: logs) { calendar.startOfDay(for: $0.reviewedAt) }
        let today = calendar.startOfDay(for: now)

        return (0..<dayCount).reversed().compactMap { offset in
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

    nonisolated private func logsInRange(
        _ logs: [StudyLogSnapshot],
        range: StatisticsTimeRange,
        calendar: Calendar,
        now: Date
    ) -> [StudyLogSnapshot] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(range.rawValue - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else {
            return []
        }
        return logs.filter { $0.reviewedAt >= start && $0.reviewedAt < end }
    }

    nonisolated private func newlyLearnedWordCount(
        allLogs: [StudyLogSnapshot],
        periodLogs: [StudyLogSnapshot]
    ) -> Int {
        let periodLogIDs = Set(periodLogs.map(\.id))
        var earliestByWordID: [UUID: StudyLogSnapshot] = [:]

        for log in allLogs {
            guard let wordID = log.wordID else { continue }
            if let earliest = earliestByWordID[wordID], earliest.reviewedAt <= log.reviewedAt {
                continue
            }
            earliestByWordID[wordID] = log
        }

        return earliestByWordID.values.filter { periodLogIDs.contains($0.id) }.count
    }

    nonisolated private func ratingDistribution(from logs: [StudyLogSnapshot]) -> RatingDistribution {
        RatingDistribution(
            againCount: logs.filter { $0.rating == .again }.count,
            hardCount: logs.filter { $0.rating == .hard }.count,
            goodCount: logs.filter { $0.rating == .good }.count,
            masteredCount: logs.filter { $0.rating == .easy }.count
        )
    }

    nonisolated private func spellingFirstPassAccuracy(
        from logs: [StudyLogSnapshot],
        words: [StudyWordSnapshot]
    ) -> SpellingFirstPassAccuracy {
        let wordsByID = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
        var passedCount = 0
        var eligibleCount = 0

        for log in logs {
            guard log.nextState != .suspended,
                  log.hasSpellingDiagnostics,
                  let wordID = log.wordID,
                  let word = wordsByID[wordID] else {
                continue
            }

            eligibleCount += 1
            if log.spellingWrongCount == 0 { passedCount += 1 }

            if containsKanji(word.expression) {
                eligibleCount += 1
                if log.readingWrongCount == 0 { passedCount += 1 }
            }
        }

        return SpellingFirstPassAccuracy(
            passedCount: passedCount,
            eligibleCount: eligibleCount
        )
    }

    nonisolated private func containsKanji(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
                || (0x20000...0x2FA1F).contains(scalar.value)
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
