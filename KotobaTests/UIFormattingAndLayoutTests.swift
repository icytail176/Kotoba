import XCTest
@testable import Kotoba

@MainActor
final class UIFormattingAndLayoutTests: XCTestCase {
    func testWordbookLayoutAdaptsAcrossWindowContentWidths() {
        XCTAssertEqual(WordbookLayoutPolicy.mode(for: 500), .compact)
        XCTAssertEqual(WordbookLayoutPolicy.mode(for: 680), .coreColumns)
        XCTAssertEqual(WordbookLayoutPolicy.mode(for: 980), .fullColumns)
        XCTAssertEqual(WordbookLayoutPolicy.mode(for: 1_220), .fullColumns)
        XCTAssertFalse(WordbookLayoutPolicy.showsSplitDetail(for: 680))
        XCTAssertTrue(WordbookLayoutPolicy.showsSplitDetail(for: 980))
    }

    func testNextReviewFormatterUsesProductRelativeRules() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 10)))

        XCTAssertEqual(NextReviewDateFormatter.string(for: now.addingTimeInterval(10 * 60), relativeTo: now, calendar: calendar), "10分钟后")
        XCTAssertEqual(NextReviewDateFormatter.string(for: now.addingTimeInterval(3 * 60 * 60), relativeTo: now, calendar: calendar), "今天")
        XCTAssertEqual(NextReviewDateFormatter.string(for: try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now)), relativeTo: now, calendar: calendar), "明天")
        XCTAssertEqual(NextReviewDateFormatter.string(for: try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: now)), relativeTo: now, calendar: calendar), "2天后")
    }

    func testShortcutReferenceIncludesActualMasteredAndHintKeys() {
        let items = KeyboardShortcutReference.sections.flatMap(\.items)
        XCTAssertTrue(items.contains { $0.action == "熟练" && $0.keys == "Delete / Backspace" })
        XCTAssertTrue(items.contains { $0.action.contains("假名提示") && $0.keys == "⌘⇧H" })
        XCTAssertTrue(items.contains { $0.action == "退出本组" && $0.keys == "Escape" })
        XCTAssertTrue(items.contains { $0.action == "返回首页" && $0.keys == "Enter" })
        XCTAssertEqual(items.filter { $0.keys == "⌘⇧H" }.count, 1)
    }
}
