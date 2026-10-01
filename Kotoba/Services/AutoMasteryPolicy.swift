import Foundation

struct AutoMasteryProgressSnapshot: Equatable, Sendable {
    let state: LearningState
    let intervalDays: Int
    let isArchived: Bool
}

enum AutoMasteryPolicy {
    /// Automatic mastery is derived from the state before the current formal
    /// rating. Reaching the 60-day cap does not master a word; the learner must
    /// complete that full interval and then submit a second consecutive Good.
    nonisolated static func shouldAutoMaster(
        progressBeforeRating: AutoMasteryProgressSnapshot,
        previousFormalRating: ReviewRating?,
        currentRating: ReviewRating
    ) -> Bool {
        progressBeforeRating.state == .review
            && progressBeforeRating.intervalDays == AppSettings.maximumReviewIntervalDays
            && !progressBeforeRating.isArchived
            && previousFormalRating == .good
            && currentRating == .good
    }
}
