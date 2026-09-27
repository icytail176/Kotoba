import XCTest
@testable import Kotoba

@MainActor
final class KotobaWindowSizingTests: XCTestCase {
    func testFallbackSizeComfortablyFitsStudyCard() {
        XCTAssertEqual(KotobaWindowSizing.defaultSize(for: nil), CGSize(width: 1_100, height: 760))
    }

    func testDefaultSizeScalesWithTypicalScreenAndKeepsMargins() {
        let size = KotobaWindowSizing.defaultSize(for: CGSize(width: 1_440, height: 900))

        XCTAssertEqual(size.width, 1_123.2, accuracy: 0.1)
        XCTAssertEqual(size.height, 738, accuracy: 0.1)
        XCTAssertLessThan(size.width, 1_440)
        XCTAssertLessThan(size.height, 900)
    }

    func testDefaultSizeIsCappedOnLargeScreenAndFitsCompactScreen() {
        XCTAssertEqual(
            KotobaWindowSizing.defaultSize(for: CGSize(width: 2_560, height: 1_440)),
            CGSize(width: 1_180, height: 840)
        )

        let compact = KotobaWindowSizing.defaultSize(for: CGSize(width: 1_000, height: 650))
        XCTAssertEqual(compact, CGSize(width: 900, height: 585))
    }
}
