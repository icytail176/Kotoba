//
//  VocabularyCSVImportServiceTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/16.
//

import SwiftData
import XCTest

@MainActor
final class VocabularyCSVImportServiceTests: XCTestCase {
    private var service: VocabularyCSVImportService!

    override func setUp() {
        super.setUp()
        service = VocabularyCSVImportService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testPreviewDoesNotModifyDatabase() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let data = csvData(
            """
            expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags
            学生,がくせい,学生,名词,私は学生です。,我是学生。,N5,学校;N5
            """
        )

        let preview = try service.makePreview(from: data, fileName: "words.csv", context: context)
        let words = try fetchWords(in: context)

        XCTAssertEqual(preview.totalRows, 1)
        XCTAssertEqual(preview.validRows, 1)
        XCTAssertEqual(words.count, 0)
    }

    func testEmptyCSVReportsParserError() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext

        XCTAssertThrowsError(
            try service.makePreview(from: Data(), fileName: "empty.csv", context: context)
        ) { error in
            XCTAssertEqual(error as? CSVParserError, .emptyFile)
        }
    }

    func testWrongHeadersReportMissingHeaderError() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let data = csvData(
            """
            expression,kana,meaningChinese
            学生,がくせい,学生
            """
        )

        XCTAssertThrowsError(
            try service.makePreview(from: data, fileName: "wrong-header.csv", context: context)
        ) { error in
            guard case VocabularyCSVImportError.missingHeaders(let headers) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertTrue(headers.contains("reading"))
            XCTAssertEqual(headers.count, 1)
        }
    }

    func testRequiredOnlyRowImportsWithOptionalFieldsEmpty() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let data = csvData(
            """
            expression,reading,meaningChinese
            猫,ねこ,猫
            """
        )

        let preview = try service.makePreview(from: data, fileName: "required-only.csv", context: context)
        let result = try service.importRows(from: preview, duplicateHandling: .skip, context: context)
        let words = try fetchWords(in: context)

        XCTAssertEqual(preview.validRows, 1)
        XCTAssertEqual(result.insertedCount, 1)
        XCTAssertEqual(words.first?.japanese, "猫")
        XCTAssertEqual(words.first?.kana, "ねこ")
        XCTAssertEqual(words.first?.chineseMeaning, "猫")
        XCTAssertEqual(words.first?.partOfSpeech, "")
        XCTAssertEqual(words.first?.exampleJapanese, "")
        XCTAssertEqual(words.first?.exampleChinese, "")
        XCTAssertEqual(words.first?.jlptLevel, "")
        XCTAssertEqual(words.first?.tags, [])
    }

    func testValidationReportsRequiredFieldsAndInvalidJLPT() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let data = csvData(
            """
            expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags
            学生,,学生,名词,私は学生です。,我是学生。,N5,学校
            食べる,たべる,吃,动词,朝ご飯を食べます。,吃早饭。,N0,动作
            ,みず,,名词,水を飲みます。,喝水。,N5,生活
            """
        )

        let preview = try service.makePreview(from: data, fileName: "invalid.csv", context: context)

        XCTAssertEqual(preview.totalRows, 3)
        XCTAssertEqual(preview.validRows, 0)
        XCTAssertEqual(preview.errorRows, 3)
        XCTAssertTrue(preview.errors[0].reason.contains("reading 必填"))
        XCTAssertTrue(preview.errors[1].reason.contains("jlptLevel"))
        XCTAssertTrue(preview.errors[2].reason.contains("expression 必填"))
        XCTAssertTrue(preview.errors[2].reason.contains("meaningChinese 必填"))
    }

    func testFileDuplicateBecomesRowError() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let data = csvData(
            """
            expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags
            学生,がくせい,学生,名词,私は学生です。,我是学生。,N5,学校
            学生,がくせい,学生2,名词,私は学生です。,我是学生。,N5,学校
            """
        )

        let preview = try service.makePreview(from: data, fileName: "duplicate.csv", context: context)

        XCTAssertEqual(preview.validRows, 1)
        XCTAssertEqual(preview.errorRows, 1)
        XCTAssertEqual(preview.errors.first?.lineNumber, 3)
        XCTAssertTrue(preview.errors.first?.reason.contains("第 2 行") ?? false)
    }

    func testPreviewCountsExistingDuplicates() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        insertWord(expression: "学生", reading: "がくせい", meaning: "旧释义", context: context)
        try context.save()
        let data = csvData(
            """
            expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags
            学生,がくせい,学生,名词,私は学生です。,我是学生。,N5,学校
            水,みず,水,名词,水を飲みます。,喝水。,N5,生活
            """
        )

        let preview = try service.makePreview(from: data, fileName: "mixed.csv", context: context)

        XCTAssertEqual(preview.validRows, 2)
        XCTAssertEqual(preview.duplicateCount, 1)
        XCTAssertEqual(preview.newCount(for: .skip), 1)
        XCTAssertEqual(preview.updateCount(for: .skip), 0)
        XCTAssertEqual(preview.updateCount(for: .update), 1)
    }

    func testImportSkipsExistingDuplicatesAndInsertsNewWords() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let existing = insertWord(expression: "学生", reading: "がくせい", meaning: "旧释义", context: context)
        try context.save()
        let data = csvData(
            """
            expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags
            学生,がくせい,新释义,名词,私は学生です。,我是学生。,N5,学校
            水,みず,水,名词,水を飲みます。,喝水。,N5,生活
            """
        )
        let preview = try service.makePreview(from: data, fileName: "skip.csv", context: context)

        let result = try service.importRows(
            from: preview,
            duplicateHandling: .skip,
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 0)
        )
        let words = try fetchWords(in: context)

        XCTAssertEqual(result.insertedCount, 1)
        XCTAssertEqual(result.updatedCount, 0)
        XCTAssertEqual(result.skippedDuplicateCount, 1)
        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(existing.chineseMeaning, "旧释义")
        XCTAssertTrue(words.contains(where: { $0.japanese == "水" && $0.progress?.state == .new }))
    }

    func testImportContinuesWhenSomeRowsHaveErrors() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let data = csvData(
            """
            expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags
            学生,がくせい,学生,名词,私は学生です。,我是学生。,N5,学校
            水,,水,名词,水を飲みます。,喝水。,N5,生活
            """
        )
        let preview = try service.makePreview(from: data, fileName: "partial.csv", context: context)

        let result = try service.importRows(from: preview, duplicateHandling: .skip, context: context)
        let words = try fetchWords(in: context)

        XCTAssertEqual(preview.validRows, 1)
        XCTAssertEqual(preview.errorRows, 1)
        XCTAssertEqual(result.insertedCount, 1)
        XCTAssertEqual(result.ignoredErrorCount, 1)
        XCTAssertEqual(words.map(\.japanese), ["学生"])
    }

    func testImportUpdatesExistingWordsWithoutResettingProgress() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let existing = insertWord(expression: "学生", reading: "がくせい", meaning: "旧释义", context: context)
        existing.progress?.reviewCount = 4
        existing.progress?.state = .review
        try context.save()
        let data = csvData(
            """
            expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags
            学生,がくせい,新释义,名词,"私は学生で、毎日勉強します。",我是学生，每天学习。,N4,学校;更新;学校
            """
        )
        let preview = try service.makePreview(from: data, fileName: "update.csv", context: context)

        let result = try service.importRows(
            from: preview,
            duplicateHandling: .update,
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 10)
        )

        XCTAssertEqual(result.insertedCount, 0)
        XCTAssertEqual(result.updatedCount, 1)
        XCTAssertEqual(existing.chineseMeaning, "新释义")
        XCTAssertEqual(existing.exampleJapanese, "私は学生で、毎日勉強します。")
        XCTAssertEqual(existing.jlptLevel, "N4")
        XCTAssertEqual(existing.tags, ["学校", "更新"])
        XCTAssertEqual(existing.progress?.reviewCount, 4)
        XCTAssertEqual(existing.progress?.state, .review)
    }

    func testRequiredOnlyUpdatePreservesExistingOptionalFieldsAndProgress() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let existing = insertWord(expression: "学生", reading: "がくせい", meaning: "旧释义", context: context)
        existing.partOfSpeech = "名词"
        existing.exampleJapanese = "私は学生です。"
        existing.exampleChinese = "我是学生。"
        existing.jlptLevel = "N5"
        existing.tags = ["学校", "N5"]
        existing.progress?.reviewCount = 4
        existing.progress?.state = .review
        try context.save()
        let data = csvData(
            """
            expression,reading,meaningChinese
            学生,がくせい,新释义
            """
        )
        let preview = try service.makePreview(from: data, fileName: "required-update.csv", context: context)

        let result = try service.importRows(
            from: preview,
            duplicateHandling: .update,
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 10)
        )

        XCTAssertEqual(result.updatedCount, 1)
        XCTAssertEqual(existing.chineseMeaning, "新释义")
        XCTAssertEqual(existing.partOfSpeech, "名词")
        XCTAssertEqual(existing.exampleJapanese, "私は学生です。")
        XCTAssertEqual(existing.exampleChinese, "我是学生。")
        XCTAssertEqual(existing.jlptLevel, "N5")
        XCTAssertEqual(existing.tags, ["学校", "N5"])
        XCTAssertEqual(existing.progress?.reviewCount, 4)
        XCTAssertEqual(existing.progress?.state, .review)
    }

    func testBlankLinesJapaneseCharactersCommaMeaningAndLongExampleImport() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let longExample = String(repeating: "図書館で静かに本を読みます。", count: 80)
        let data = csvData(
            """
            expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags

            図書館,としょかん,"图书馆, 藏书楼",名词,\(longExample),在图书馆安静地读书。,N4,場所;読書

            """
        )

        let preview = try service.makePreview(from: data, fileName: "long-example.csv", context: context)
        let result = try service.importRows(from: preview, duplicateHandling: .skip, context: context)
        let words = try fetchWords(in: context)

        XCTAssertEqual(preview.totalRows, 1)
        XCTAssertEqual(preview.validRows, 1)
        XCTAssertEqual(result.insertedCount, 1)
        XCTAssertEqual(words.first?.japanese, "図書館")
        XCTAssertEqual(words.first?.chineseMeaning, "图书馆, 藏书楼")
        XCTAssertEqual(words.first?.exampleJapanese, longExample)
        XCTAssertEqual(words.first?.tags, ["場所", "読書"])
    }

    func testQuotedCommaAndEscapedQuoteSurviveImport() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let data = csvData(
            """
            expression,reading,meaningChinese,partOfSpeech,exampleJapanese,exampleChinese,jlptLevel,tags
            影響,えいきょう,影响,名词,"先生は「""影響、あります""」と言いました。","老师说：“有影响。”",N3,抽象;N3
            """
        )
        let preview = try service.makePreview(from: data, fileName: "quotes.csv", context: context)

        _ = try service.importRows(from: preview, duplicateHandling: .skip, context: context)
        let words = try fetchWords(in: context)

        XCTAssertEqual(words.first?.exampleJapanese, "先生は「\"影響、あります\"」と言いました。")
        XCTAssertEqual(words.first?.exampleChinese, "老师说：“有影响。”")
    }

    func testDuplicateDetectionIsScopedToTargetWordBook() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let bookA = WordBook(name: "N5")
        let bookB = WordBook(name: "校园日语")
        context.insert(bookA)
        context.insert(bookB)
        insertWord(expression: "先生", reading: "せんせい", meaning: "老师", context: context, wordBook: bookA)
        try context.save()

        let data = csvData(
            """
            expression,reading,meaningChinese
            先生,せんせい,老师
            """
        )

        let previewForBookB = try service.makePreview(
            from: data,
            fileName: "school.csv",
            context: context,
            targetWordBook: bookB
        )
        let previewForBookA = try service.makePreview(
            from: data,
            fileName: "n5.csv",
            context: context,
            targetWordBook: bookA
        )

        XCTAssertEqual(previewForBookB.duplicateCount, 0)
        XCTAssertEqual(previewForBookA.duplicateCount, 1)
    }

    func testImportIntoExistingWordBookUpdatesOnlyThatBookAndPreservesProgress() throws {
        let container = try makeInMemoryTestContainer()
        let context = container.mainContext
        let bookA = WordBook(name: "N5")
        let bookB = WordBook(name: "校园日语")
        context.insert(bookA)
        context.insert(bookB)
        let existingA = insertWord(expression: "先生", reading: "せんせい", meaning: "旧释义A", context: context, wordBook: bookA)
        let existingB = insertWord(expression: "先生", reading: "せんせい", meaning: "旧释义B", context: context, wordBook: bookB)
        existingB.progress?.state = .review
        existingB.progress?.reviewCount = 9
        try context.save()

        let data = csvData(
            """
            expression,reading,meaningChinese
            先生,せんせい,新释义B
            """
        )
        let preview = try service.makePreview(
            from: data,
            fileName: "update.csv",
            context: context,
            targetWordBook: bookB
        )

        let result = try service.importRows(
            from: preview,
            duplicateHandling: .update,
            context: context,
            target: .existingWordBook(bookB.id)
        )

        XCTAssertEqual(result.updatedCount, 1)
        XCTAssertEqual(result.wordBookID, bookB.id)
        XCTAssertEqual(existingA.chineseMeaning, "旧释义A")
        XCTAssertEqual(existingB.chineseMeaning, "新释义B")
        XCTAssertEqual(existingB.progress?.state, .review)
        XCTAssertEqual(existingB.progress?.reviewCount, 9)
    }

    private func csvData(_ csv: String, file: StaticString = #filePath, line: UInt = #line) -> Data {
        guard let data = csv.data(using: .utf8) else {
            XCTFail("Failed to encode CSV as UTF-8", file: file, line: line)
            return Data()
        }

        return data
    }

    @discardableResult
    private func insertWord(
        expression: String,
        reading: String,
        meaning: String,
        context: ModelContext,
        wordBook: WordBook? = nil
    ) -> VocabularyWord {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let word = VocabularyWord(
            japanese: expression,
            kana: reading,
            chineseMeaning: meaning,
            partOfSpeech: "名词",
            jlptLevel: "N5",
            createdAt: now,
            updatedAt: now,
            wordBook: wordBook
        )
        word.progress = LearningProgress(
            state: .new,
            dueAt: now,
            createdAt: now,
            updatedAt: now,
            word: word
        )
        context.insert(word)
        return word
    }

    private func fetchWords(in context: ModelContext) throws -> [VocabularyWord] {
        try context.fetch(FetchDescriptor<VocabularyWord>())
    }
}
