//
//  CSVParserTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/16.
//

import XCTest
@testable import Kotoba

final class CSVParserTests: XCTestCase {
    func testParsesQuotedCommasAndEscapedQuotes() throws {
        let csv = """
        expression,exampleJapanese
        確認,"先生は「""確認、お願いします""」と言いました。"
        """

        let table = try CSVParser().parse(csv)

        XCTAssertEqual(table.headers, ["expression", "exampleJapanese"])
        XCTAssertEqual(table.rows.count, 1)
        XCTAssertEqual(table.rows.first?.fields[0], "確認")
        XCTAssertEqual(table.rows.first?.fields[1], "先生は「\"確認、お願いします\"」と言いました。")
    }

    func testIgnoresEmptyLinesAndKeepsPhysicalLineNumbers() throws {
        let csv = """
        expression,reading

        学生,がくせい

        水,みず
        """

        let table = try CSVParser().parse(csv)

        XCTAssertEqual(table.rows.map(\.lineNumber), [3, 5])
        XCTAssertEqual(table.rows.map { $0.fields[0] }, ["学生", "水"])
    }

    func testParsesQuotedNewlineAsSingleField() throws {
        let csv = "expression,exampleJapanese\n確認,\"一行目\n二行目\"\n"

        let table = try CSVParser().parse(csv)

        XCTAssertEqual(table.rows.count, 1)
        XCTAssertEqual(table.rows.first?.lineNumber, 2)
        XCTAssertEqual(table.rows.first?.fields[1], "一行目\n二行目")
    }

    func testThrowsForUnterminatedQuote() {
        let csv = "expression,exampleJapanese\n確認,\"未完成\n"

        XCTAssertThrowsError(try CSVParser().parse(csv)) { error in
            XCTAssertEqual(error as? CSVParserError, .unterminatedQuotedField(line: 2))
        }
    }
}
