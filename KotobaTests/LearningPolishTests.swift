import XCTest
@testable import Kotoba

final class LearningPolishTests: XCTestCase {
    func testCompletionActionUsesProvidedReturnHomeAction() {
        var callCount = 0
        let action = StudyCompletionAction { callCount += 1 }

        action.perform()
        action.perform()
        action.perform()

        XCTAssertEqual(callCount, 1)
    }

    func testRomajiCoversCoreKanaRules() {
        XCTAssertEqual(JapaneseRomajiFormatter.string(from: "あいうえお"), "aiueo")
        XCTAssertEqual(JapaneseRomajiFormatter.string(from: "がざだばぱ"), "gazadabapa")
        XCTAssertEqual(JapaneseRomajiFormatter.string(from: "べんきょう"), "benkyō")
        XCTAssertEqual(JapaneseRomajiFormatter.string(from: "がっこう"), "gakkō")
        XCTAssertEqual(JapaneseRomajiFormatter.string(from: "しんよう"), "shin'yō")
        XCTAssertEqual(JapaneseRomajiFormatter.string(from: "せんせい"), "sensei")
    }

    func testRomajiCoversKatakanaAndCommonLoanwordCombinations() {
        XCTAssertEqual(JapaneseRomajiFormatter.string(from: "コンピューター"), "konpyūtā")
        XCTAssertEqual(JapaneseRomajiFormatter.string(from: "ティッシュ"), "tisshu")
        XCTAssertEqual(JapaneseRomajiFormatter.string(from: "ヴァイオリン"), "vaiorin")
        XCTAssertEqual(JapaneseRomajiFormatter.string(from: "ファイル"), "fairu")
        XCTAssertEqual(JapaneseRomajiFormatter.string(from: "チェーン"), "chēn")
    }

    func testPitchAccentUsesOnlyFormalTagsAndHidesMissingOrInvalidValues() {
        XCTAssertEqual(
            PitchAccentPresentation.make(tags: ["eggrolls", "音调:⓪"])?.displayText,
            "[0]"
        )
        XCTAssertEqual(
            PitchAccentPresentation.make(tags: ["音调:①+⓪"])?.displayText,
            "[1+0]"
        )
        XCTAssertEqual(
            PitchAccentPresentation.make(tags: ["音调:⓪③"])?.displayText,
            "[0/3]"
        )
        XCTAssertEqual(
            PitchAccentPresentation.make(tags: ["音调:①+①、③"])?.displayText,
            "[1+1, 3]"
        )
        XCTAssertNil(PitchAccentPresentation.make(tags: []))
        XCTAssertNil(PitchAccentPresentation.make(tags: ["音调:"]))
        XCTAssertNil(PitchAccentPresentation.make(tags: ["音调:unknown"]))
    }

    func testEveryBundledPitchAccentTagHasASupportedFormalFormat() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kotoba/Resources")
        var pitchTagCount = 0

        for definition in BuiltInWordBookDefinition.all {
            let text = try String(
                contentsOf: resources.appendingPathComponent(definition.fileName),
                encoding: .utf8
            )
            let table = try CSVParser().parse(text)
            for row in table.rows where row.fields.count == 8 {
                let tags = row.fields[7].split(separator: ";").map(String.init)
                guard tags.contains(where: { $0.hasPrefix("音调:") }) else { continue }
                pitchTagCount += 1
                XCTAssertNotNil(
                    PitchAccentPresentation.make(tags: tags),
                    "Unsupported pitch tag at \(definition.fileName):\(row.lineNumber)"
                )
            }
        }

        XCTAssertEqual(pitchTagCount, 10_398)
    }

    func testAttributionSourceModelContainsVerifiedSources() {
        let builtIn = AppAttribution.builtInVocabulary
        XCTAssertEqual(builtIn.shortName, "egg rolls")
        XCTAssertEqual(builtIn.url.absoluteString, "https://github.com/5mdld/anki-jlpt-decks")
        XCTAssertEqual(builtIn.licenseName, "CC BY-NC 4.0")
        XCTAssertTrue(builtIn.modificationNote.contains("修改"))

        let loanword = AppAttribution.loanwordEtymology
        XCTAssertEqual(loanword.shortName, "JMdict")
        XCTAssertEqual(loanword.licenseName, "CC BY-SA 4.0")
        XCTAssertEqual(AppAttribution.all.count, 2)
    }

    func testAppVersionInfoReadsBundleValuesWithoutHardcodedFallbackVersion() {
        let info = AppVersionInfo.make(infoDictionary: [
            "CFBundleShortVersionString": "0.2.1",
            "CFBundleVersion": "37"
        ])

        XCTAssertEqual(info.version, "0.2.1")
        XCTAssertEqual(info.build, "37")
        XCTAssertEqual(info.displayText, "版本 0.2.1（构建 37）")
        XCTAssertEqual(AppVersionInfo.make(infoDictionary: nil).displayText, "版本 —（构建 —）")
    }

    func testLoanwordPresentationHidesMissingOptionalEtymologyForOrdinaryWord() {
        let word = VocabularyWord(
            japanese: "猫",
            kana: "ねこ",
            chineseMeaning: "猫",
            jlptLevel: "N5"
        )
        XCTAssertNil(LoanwordEtymologyPresentation.make(for: word))
        XCTAssertEqual(StudyCardMeaningPresentation.make(for: word).inlineText, "猫")
    }

    func testLoanwordDisplayPolicyNormalizesCurrentLanguagesAndConservativelyHidesUnknownValues() {
        let cases: [(String, LoanwordEtymologyDisplayPolicy.NormalizedLanguage, String)] = [
            ("eng", .english, "英语"),
            ("ger", .german, "德语"),
            ("fre", .french, "法语"),
            ("dut", .dutch, "荷兰语"),
            ("por", .portuguese, "葡萄牙语"),
            ("ita", .italian, "意大利语"),
            ("rus", .russian, "俄语"),
            ("lat", .latin, "拉丁语"),
            ("chi", .chinese, "汉语")
        ]

        for (raw, normalized, localizedName) in cases {
            XCTAssertEqual(LoanwordEtymologyDisplayPolicy.normalizedLanguage(for: raw), normalized)
            XCTAssertEqual(LoanwordEtymologyDisplayPolicy.localizedLanguageName(for: raw), localizedName)
        }
        XCTAssertEqual(LoanwordEtymologyDisplayPolicy.normalizedLanguage(for: " 漢語 "), .chinese)
        XCTAssertEqual(LoanwordEtymologyDisplayPolicy.normalizedLanguage(for: "Chinese-origin"), .chinese)
        XCTAssertEqual(LoanwordEtymologyDisplayPolicy.normalizedLanguage(for: "Sino-origin"), .chinese)
        XCTAssertNil(LoanwordEtymologyDisplayPolicy.normalizedLanguage(for: "unknown"))
        XCTAssertFalse(LoanwordEtymologyDisplayPolicy.shouldDisplay(
            sourceTerm: "source", sourceLanguage: nil, isWasei: false, isPartial: false
        ))
        XCTAssertFalse(LoanwordEtymologyDisplayPolicy.shouldDisplay(
            sourceTerm: "source", sourceLanguage: "unknown", isWasei: false, isPartial: false
        ))
        XCTAssertTrue(LoanwordEtymologyDisplayPolicy.shouldDisplay(
            sourceTerm: "source", sourceLanguage: nil, isWasei: true, isPartial: false
        ))
        XCTAssertFalse(LoanwordEtymologyDisplayPolicy.shouldDisplay(
            sourceTerm: "来源", sourceLanguage: "chi", isWasei: false, isPartial: true
        ))
    }

    func testStudyCardMeaningPresentationHandlesLanguageWaseiPartialAndEveryCardPhase() throws {
        let word = VocabularyWord(
            japanese: "テレビ",
            kana: "テレビ",
            chineseMeaning: "电视",
            jlptLevel: "N5",
            loanwordSourceTerm: "television",
            loanwordSourceLanguageCode: "eng"
        )
        let dueAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let newCard = StudySession.Item(id: word.id, word: word, kind: .newWord, dueAt: dueAt)
        let reviewCard = StudySession.Item(id: word.id, word: word, kind: .dueReview, dueAt: dueAt)
        let reinforcementCard = reviewCard

        for item in [newCard, reviewCard, reinforcementCard] {
            let presentation = StudyCardMeaningPresentation.make(for: item)
            XCTAssertEqual(presentation.sourceMetadata, "television（英语）")
            XCTAssertEqual(presentation.inlineText, "电视 · television（英语）")
            XCTAssertEqual(presentation.accessibilityText, "释义，电视。词源，英语 television")
        }

        word.loanwordSourceLanguageCode = nil
        word.loanwordIsPartial = false
        XCTAssertEqual(StudyCardMeaningPresentation.make(for: word).inlineText, "电视")
        XCTAssertNil(StudyCardMeaningPresentation.make(for: word).sourceMetadata)

        word.loanwordSourceTerm = "salary + man"
        word.loanwordSourceLanguageCode = "eng"
        word.loanwordIsWasei = true
        XCTAssertEqual(StudyCardMeaningPresentation.make(for: word).inlineText, "电视 · salary + man（和制英语）")

        word.loanwordSourceTerm = "form"
        word.loanwordIsWasei = false
        word.loanwordIsPartial = true
        let partial = StudyCardMeaningPresentation.make(for: word)
        XCTAssertEqual(partial.inlineText, "电视 · form（英语） · 部分词源")
        XCTAssertEqual(partial.accessibilityText, "释义，电视。部分词源，英语 form")
    }

    func testChineseOriginMetadataIsRetainedButHiddenForEveryStudyCardPhase() {
        let word = VocabularyWord(
            japanese: "ラーメン",
            kana: "ラーメン",
            chineseMeaning: "拉面",
            jlptLevel: "N5",
            loanwordSourceTerm: "lāmiàn",
            loanwordSourceLanguageCode: "chi"
        )
        let dueAt = Date(timeIntervalSinceReferenceDate: 2_000)
        let newCard = StudySession.Item(id: word.id, word: word, kind: .newWord, dueAt: dueAt)
        let reviewCard = StudySession.Item(id: word.id, word: word, kind: .dueReview, dueAt: dueAt)
        // Reinforcement presents the same StudySession.Item through StudyCardView.
        let reinforcementCard = reviewCard

        XCTAssertEqual(word.loanwordSourceTerm, "lāmiàn")
        XCTAssertEqual(word.loanwordSourceLanguageCode, "chi")
        XCTAssertNil(LoanwordEtymologyPresentation.make(for: word))
        for item in [newCard, reviewCard, reinforcementCard] {
            let presentation = StudyCardMeaningPresentation.make(for: item)
            XCTAssertNil(presentation.sourceMetadata)
            XCTAssertEqual(presentation.inlineText, "拉面")
            XCTAssertEqual(presentation.accessibilityText, "释义，拉面")
        }

        word.loanwordIsPartial = true
        XCTAssertNil(LoanwordEtymologyPresentation.make(for: word))
    }
}
