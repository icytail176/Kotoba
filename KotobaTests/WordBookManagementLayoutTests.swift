import XCTest
@testable import Kotoba

@MainActor
final class WordBookManagementLayoutTests: XCTestCase {
    func testNarrowContentUsesStackedLayout() {
        XCTAssertEqual(WordBookManagementLayoutPolicy.mode(for: 599), .stacked)
        XCTAssertEqual(WordBookManagementLayoutPolicy.mode(for: 600), .split)
    }

    func testSplitLayoutKeepsAtLeastThreeHundredTwentyPointsForDetail() {
        XCTAssertEqual(WordBookManagementLayoutPolicy.listMaximumWidth(for: 600), 280)
        XCTAssertEqual(WordBookManagementLayoutPolicy.listMaximumWidth(for: 640), 320)
        XCTAssertEqual(WordBookManagementLayoutPolicy.listMaximumWidth(for: 900), 360)
    }

    func testPartOfSpeechColumnOnlyAppearsWhenDetailIsWideEnough() {
        XCTAssertFalse(WordBookManagementLayoutPolicy.showsPartOfSpeech(for: 519))
        XCTAssertTrue(WordBookManagementLayoutPolicy.showsPartOfSpeech(for: 520))
    }

    func testNarrowDetailUsesReducedHorizontalPadding() {
        XCTAssertEqual(WordBookManagementLayoutPolicy.detailHorizontalPadding(for: 459), 16)
        XCTAssertEqual(WordBookManagementLayoutPolicy.detailHorizontalPadding(for: 460), 24)
    }
}
