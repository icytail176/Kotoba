import XCTest
@testable import Kotoba

final class KanaChartTests: XCTestCase {
    func testSeionKeepsFiveColumnStructureAndRequiredEmptyPositions() throws {
        XCTAssertTrue(KanaChartData.seionRows.allSatisfy { $0.entries.count == 5 })

        let ya = try row("や行", in: KanaChartData.seionRows)
        XCTAssertEqual(ya.entries[0]?.romaji, "ya")
        XCTAssertNil(ya.entries[1])
        XCTAssertEqual(ya.entries[2]?.romaji, "yu")
        XCTAssertNil(ya.entries[3])
        XCTAssertEqual(ya.entries[4]?.romaji, "yo")

        let wa = try row("わ行", in: KanaChartData.seionRows)
        XCTAssertEqual(wa.entries.map { $0?.romaji }, ["wa", "wi", nil, "we", "wo"])
    }

    func testHistoricalKanaMappingsAndMetadata() throws {
        let wa = try row("わ行", in: KanaChartData.seionRows)
        let wi = try XCTUnwrap(wa.entries[1])
        let we = try XCTUnwrap(wa.entries[3])

        XCTAssertEqual(wi.glyph(for: .hiragana), "ゐ")
        XCTAssertEqual(wi.glyph(for: .katakana), "ヰ")
        XCTAssertEqual(wi.romaji, "wi")
        XCTAssertTrue(wi.isHistorical)
        XCTAssertEqual(we.glyph(for: .hiragana), "ゑ")
        XCTAssertEqual(we.glyph(for: .katakana), "ヱ")
        XCTAssertEqual(we.romaji, "we")
        XCTAssertTrue(we.isHistorical)
        XCTAssertTrue(wi.accessibilityLabel(for: .hiragana).contains("现代日语通常不使用"))

        let ka = try XCTUnwrap(try row("か行", in: KanaChartData.seionRows).entries[0])
        XCTAssertFalse(ka.isHistorical)
        XCTAssertEqual(ka.accessibilityLabel(for: .katakana), "カ，ka")
    }

    func testDakuonHandakuonAndYoonCoverage() throws {
        XCTAssertEqual(KanaChartData.dakuonHandakuonRows.count, 5)
        XCTAssertEqual(KanaChartData.dakuonHandakuonRows.flatMap(\.entries).compactMap { $0 }.count, 25)

        let expected: [(String, String, String)] = [
            ("きゃ行", "きゃ", "キャ"),
            ("しゃ行", "しゃ", "シャ"),
            ("ちゃ行", "ちゃ", "チャ"),
            ("ぎゃ行", "ぎゃ", "ギャ"),
            ("ぴゃ行", "ぴょ", "ピョ")
        ]
        for (label, hiragana, katakana) in expected {
            let entries = try row(label, in: KanaChartData.yoonRows).entries.compactMap { $0 }
            let entry = try XCTUnwrap(entries.first { $0.hiragana == hiragana })
            XCTAssertEqual(entry.katakana, katakana)
        }
    }

    func testSupportedWindowWidthsLeavePositiveFlexibleCellSpace() {
        for width in [720.0, 900.0, 1_200.0, 1_440.0] {
            XCTAssertGreaterThan(KanaChartLayoutPolicy.estimatedCellWidth(for: width, columnCount: 5), 0)
        }
        XCTAssertGreaterThan(KanaChartLayoutPolicy.estimatedCellWidth(for: 420, columnCount: 5), 50)
    }

    private func row(_ label: String, in rows: [KanaRow]) throws -> KanaRow {
        try XCTUnwrap(rows.first { $0.label == label })
    }
}
