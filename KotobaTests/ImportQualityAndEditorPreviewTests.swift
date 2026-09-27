//
//  ImportQualityAndEditorPreviewTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/18.
//

import SwiftData
import XCTest
@testable import Kotoba

@MainActor
final class ImportQualityAndEditorPreviewTests: XCTestCase {
    func testImportQualityReportsCriticalWarningAndInfoIssues() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let existingBook = WordBook(name: "既有词书")
        let targetBook = WordBook(name: "目标词书")
        context.insert(existingBook)
        context.insert(targetBook)
        insertWord(expression: "学生", reading: "がくせい", context: context, wordBook: existingBook)
        try context.save()

        let data = csvData(
            """
            expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags
            学生,がくせい,学生,名词,,,N5,学校；基础
            帰る,かえる,回去,动词,家に帰ります。,回家。,N4,动作
            ,たべる,吃,一段动词,朝ご飯を食べます。,吃早饭。,N0,动作
            """
        )
        let preview = try VocabularyCSVImportService().makePreview(
            from: data,
            fileName: "quality.csv",
            context: context,
            targetWordBook: targetBook
        )
        let report = try VocabularyImportQualityService().makeReport(
            preview: preview,
            context: context,
            targetWordBook: targetBook
        )

        XCTAssertEqual(report.criticalCount, 1)
        XCTAssertTrue(report.warningCount >= 2)
        XCTAssertTrue(report.infoCount >= 2)
        XCTAssertTrue(report.issues.contains { $0.reason.contains("中文分号") })
        XCTAssertTrue(report.issues.contains { $0.reason.contains("其他词书") })
        XCTAssertTrue(report.issues.contains { $0.reason.contains("只有“动词”") })
        XCTAssertTrue(report.makeCSVReport().contains("severity,lineNumber,expression,reason"))
    }

    func testEditorPreviewRecognizesConjugationAndDoesNotWriteCache() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let service = WordEditorPreviewService()
        var draft = WordEditorDraft()
        draft.expression = "帰る"
        draft.reading = "かえる"
        draft.meaningChinese = "回去"
        draft.partOfSpeech = "五段动词"

        let preview = service.makePreview(from: draft)

        XCTAssertEqual(preview.conjugationClass, .godanVerb)
        XCTAssertTrue(preview.forms.contains { $0.type == .negative && $0.surface == "帰らない" })
        XCTAssertFalse(preview.requiresManualReview)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<VocabularyWord>()), 0)
    }

    func testEditorPreviewHandlesIchidanKireiAndAmbiguousVerb() {
        let service = WordEditorPreviewService()
        var ichidan = WordEditorDraft()
        ichidan.expression = "食べる"
        ichidan.reading = "たべる"
        ichidan.meaningChinese = "吃"
        ichidan.partOfSpeech = "一段动词"

        var kirei = WordEditorDraft()
        kirei.expression = "きれい"
        kirei.reading = "きれい"
        kirei.meaningChinese = "漂亮"
        kirei.partOfSpeech = "な形容词"

        var ambiguous = WordEditorDraft()
        ambiguous.expression = "帰る"
        ambiguous.reading = "かえる"
        ambiguous.meaningChinese = "回去"
        ambiguous.partOfSpeech = "动词"

        XCTAssertEqual(service.makePreview(from: ichidan).conjugationClass, .ichidanVerb)
        XCTAssertEqual(service.makePreview(from: kirei).conjugationClass, .naAdjective)
        XCTAssertTrue(service.makePreview(from: ambiguous).requiresManualReview)
        XCTAssertTrue(service.makePreview(from: ambiguous).warnings.contains { $0.contains("只有“动词”") })
    }

    private func csvData(_ csv: String, file: StaticString = #filePath, line: UInt = #line) -> Data {
        guard let data = csv.data(using: .utf8) else {
            XCTFail("Failed to encode CSV as UTF-8", file: file, line: line)
            return Data()
        }

        return data
    }

    private func insertWord(
        expression: String,
        reading: String,
        context: ModelContext,
        wordBook: WordBook
    ) {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let word = VocabularyWord(
            japanese: expression,
            kana: reading,
            chineseMeaning: expression,
            partOfSpeech: "名词",
            jlptLevel: "N5",
            createdAt: now,
            updatedAt: now,
            wordBook: wordBook
        )
        context.insert(word)
    }
}
