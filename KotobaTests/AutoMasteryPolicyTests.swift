import XCTest
@testable import Kotoba

final class AutoMasteryPolicyTests: XCTestCase {
    func testRequiresReviewAtSixtyDaysAndTwoConsecutiveFormalGoods() {
        XCTAssertFalse(shouldAutoMaster(intervalDays: 32, previous: .good, current: .good))
        XCTAssertTrue(shouldAutoMaster(intervalDays: 60, previous: .good, current: .good))
        XCTAssertFalse(shouldAutoMaster(intervalDays: 60, previous: .hard, current: .good))
        XCTAssertFalse(shouldAutoMaster(intervalDays: 60, previous: .good, current: .hard))
        XCTAssertFalse(shouldAutoMaster(intervalDays: 60, previous: nil, current: .good))
    }

    func testRejectsSuspendedAndArchivedWords() {
        XCTAssertFalse(shouldAutoMaster(
            state: .suspended,
            intervalDays: 60,
            previous: .good,
            current: .good
        ))
        XCTAssertFalse(shouldAutoMaster(
            intervalDays: 60,
            previous: .good,
            current: .good,
            isArchived: true
        ))
    }

    private func shouldAutoMaster(
        state: LearningState = .review,
        intervalDays: Int,
        previous: ReviewRating?,
        current: ReviewRating,
        isArchived: Bool = false
    ) -> Bool {
        AutoMasteryPolicy.shouldAutoMaster(
            progressBeforeRating: AutoMasteryProgressSnapshot(
                state: state,
                intervalDays: intervalDays,
                isArchived: isArchived
            ),
            previousFormalRating: previous,
            currentRating: current
        )
    }
}
