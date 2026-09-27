import Foundation

enum NextReviewDateFormatter {
    static func string(
        for date: Date,
        relativeTo now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let interval = date.timeIntervalSince(now)
        if interval <= 0 {
            return "现在"
        }

        if interval < 90 * 60 {
            let minutes = max(1, Int(ceil(interval / 60)))
            return "\(minutes)分钟后"
        }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let dayDifference = calendar.dateComponents([.day], from: startOfToday, to: startOfDate).day ?? 0

        switch dayDifference {
        case 0:
            return "今天"
        case 1:
            return "明天"
        case 2...6:
            return "\(dayDifference)天后"
        default:
            return date.formatted(
                .dateTime
                    .year()
                    .month(.abbreviated)
                    .day()
                    .locale(Locale(identifier: "zh-Hans"))
            )
        }
    }
}
