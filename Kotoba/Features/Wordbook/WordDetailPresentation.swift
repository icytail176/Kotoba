import Foundation

enum WordReviewHistoryPresentation {
    static let defaultLimit = 10

    struct Row: Identifiable, Equatable {
        let id: UUID
        let reviewedAtText: String
        let ratingText: String
        let transitionText: String
    }

    static func makeRow(
        from log: ReviewLog,
        locale: Locale = Locale(identifier: "zh-Hans")
    ) -> Row {
        Row(
            id: log.id,
            reviewedAtText: log.reviewedAt.formatted(
                .dateTime
                    .month(.abbreviated)
                    .day()
                    .hour()
                    .minute()
                    .locale(locale)
            ),
            ratingText: ratingText(for: log.rating),
            transitionText: transitionText(for: log)
        )
    }

    static func ratingText(for rating: ReviewRating) -> String {
        switch rating {
        case .again: "忘记"
        case .hard: "模糊"
        case .good: "认识"
        case .easy: "熟练"
        }
    }

    static func transitionText(for log: ReviewLog) -> String {
        let previous: String
        if log.nextState == .relearning {
            previous = stateText(log.previousState)
        } else if log.previousState == .review, log.previousIntervalDays > 0 {
            previous = "\(log.previousIntervalDays) 天"
        } else {
            previous = stateText(log.previousState)
        }

        let next: String
        if log.nextState == .suspended {
            next = "已熟练"
        } else if log.nextState == .review, log.nextIntervalDays > 0 {
            next = "\(log.nextIntervalDays) 天"
        } else {
            next = stateText(log.nextState)
        }

        return "\(previous) → \(next)"
    }

    private static func stateText(_ state: LearningState) -> String {
        switch state {
        case .new: "未学习"
        case .learning: "学习"
        case .review: "复习"
        case .relearning: "重新学习"
        case .suspended: "已熟练"
        }
    }
}

struct WordDetailLearningPresentation: Equatable {
    let stateName: String
    let intervalText: String?
    let dueText: String?
    let reviewCountText: String?
    let lapseCountText: String?
    let lastReviewedText: String?
    let difficultReason: String?

    static func make(
        progress: LearningProgress?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Self {
        guard let progress else {
            return Self(
                stateName: "未学习",
                intervalText: nil,
                dueText: nil,
                reviewCountText: nil,
                lapseCountText: nil,
                lastReviewedText: nil,
                difficultReason: nil
            )
        }

        let stateName = LearningStatePresentation.name(for: progress.state)

        let showsSchedule = [.learning, .relearning, .review].contains(progress.state)
        let lastReviewedText = progress.lastReviewedAt?.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
                .locale(Locale(identifier: "zh-Hans"))
        )

        return Self(
            stateName: stateName,
            intervalText: showsSchedule && progress.intervalDays > 0 ? "\(progress.intervalDays) 天" : nil,
            dueText: showsSchedule
                ? NextReviewDateFormatter.string(for: progress.dueAt, relativeTo: now, calendar: calendar)
                : nil,
            reviewCountText: progress.reviewCount > 0 ? "\(progress.reviewCount)" : nil,
            lapseCountText: progress.lapseCount > 0 ? "\(progress.lapseCount)" : nil,
            lastReviewedText: lastReviewedText,
            difficultReason: progress.lapseCount >= 2 ? "遗忘 \(progress.lapseCount) 次" : nil
        )
    }

    static func canResetToUnlearned(
        progress: LearningProgress?,
        reviewLogCount: Int
    ) -> Bool {
        if let state = progress?.state, state != .new {
            return true
        }
        return reviewLogCount > 0
    }
}

struct WordDetailLexicalPresentation: Equatable {
    let readingLine: String
    let readingAccessibilityLabel: String
    let meaningLine: String
    let meaningAccessibilityLabel: String

    static func make(for word: VocabularyWord) -> Self {
        let reading = word.kana.trimmingCharacters(in: .whitespacesAndNewlines)
        let romaji = JapaneseRomajiFormatter.string(from: reading)
        let pitch = PitchAccentPresentation.make(tags: word.tags)
        let readingComponents = [
            reading.isEmpty ? nil : reading,
            romaji.isEmpty ? nil : romaji,
            pitch?.displayText
        ].compactMap { $0 }
        let spokenComponents = [
            reading.isEmpty ? nil : "读音，\(reading)",
            romaji.isEmpty ? nil : "罗马音，\(romaji)",
            pitch?.accessibilityText
        ].compactMap { $0 }
        let meaning = StudyCardMeaningPresentation.make(for: word)

        return Self(
            readingLine: readingComponents.joined(separator: " · "),
            readingAccessibilityLabel: spokenComponents.joined(separator: "。"),
            meaningLine: meaning.inlineText,
            meaningAccessibilityLabel: meaning.accessibilityText
        )
    }
}
