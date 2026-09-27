//
//  VocabularyCSVExportServiceTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/16.
//

import XCTest
@testable import Kotoba

final class VocabularyCSVExportServiceTests: XCTestCase {
    func testExportEscapesCommasQuotesAndNewlines() {
        let service = VocabularyCSVExportService()
        let csv = service.makeCSV(from: [
            VocabularyExportRow(
                expression: "食べる",
                reading: "たべる",
                meaningChinese: "吃, 食用",
                partOfSpeech: "动词",
                exampleJapanese: "彼は「ご飯」を食べる\n水も飲む。",
                exampleChinese: "他说\"好\"。",
                jlptLevel: "N5",
                tags: ["生活", "动作"]
            )
        ])

        XCTAssertTrue(csv.hasPrefix("expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags\n"))
        XCTAssertTrue(csv.contains("\"吃, 食用\""))
        XCTAssertTrue(csv.contains("\"彼は「ご飯」を食べる\n水も飲む。\""))
        XCTAssertTrue(csv.contains("\"他说\"\"好\"\"。\""))
        XCTAssertTrue(csv.contains("生活;动作"))
        XCTAssertEqual(try? CSVParser().parse(csv).headers.count, 8)
        XCTAssertEqual(
            try? CSVParser().parse(csv).headers,
            ["expression", "reading", "meaningChinese", "partOfSpeech", "exampleJapanese", "exampleChinese", "jlptLevel", "tags"]
        )
    }
}
