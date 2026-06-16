//
//  SampleVocabularyWords.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation

enum SampleVocabularyWords {
    static func makeWords(referenceDate: Date = Date()) -> [VocabularyWord] {
        [
            makeWord(
                japanese: "学生",
                kana: "がくせい",
                chineseMeaning: "学生",
                partOfSpeech: "名词",
                jlptLevel: "N5",
                exampleJapanese: "私は学生です。",
                exampleChinese: "我是学生。",
                tags: ["学校", "N5"],
                referenceDate: referenceDate
            ),
            makeWord(
                japanese: "水",
                kana: "みず",
                chineseMeaning: "水",
                partOfSpeech: "名词",
                jlptLevel: "N5",
                exampleJapanese: "水を飲みます。",
                exampleChinese: "喝水。",
                tags: ["生活", "N5"],
                referenceDate: referenceDate
            ),
            makeWord(
                japanese: "食べる",
                kana: "たべる",
                chineseMeaning: "吃",
                partOfSpeech: "动词",
                jlptLevel: "N5",
                exampleJapanese: "朝ご飯を食べます。",
                exampleChinese: "吃早饭。",
                tags: ["动作", "N5"],
                referenceDate: referenceDate
            ),
            makeWord(
                japanese: "便利",
                kana: "べんり",
                chineseMeaning: "方便",
                partOfSpeech: "形容动词",
                jlptLevel: "N4",
                exampleJapanese: "このアプリは便利です。",
                exampleChinese: "这个应用很方便。",
                tags: ["评价", "N4"],
                referenceDate: referenceDate
            ),
            makeWord(
                japanese: "準備",
                kana: "じゅんび",
                chineseMeaning: "准备",
                partOfSpeech: "名词/サ变动词",
                jlptLevel: "N4",
                exampleJapanese: "旅行の準備をします。",
                exampleChinese: "做旅行的准备。",
                tags: ["动作", "N4"],
                referenceDate: referenceDate
            ),
            makeWord(
                japanese: "間に合う",
                kana: "まにあう",
                chineseMeaning: "赶得上，来得及",
                partOfSpeech: "动词",
                jlptLevel: "N4",
                exampleJapanese: "電車に間に合いました。",
                exampleChinese: "赶上了电车。",
                tags: ["时间", "N4"],
                referenceDate: referenceDate
            ),
            makeWord(
                japanese: "確認",
                kana: "かくにん",
                chineseMeaning: "确认",
                partOfSpeech: "名词/サ变动词",
                jlptLevel: "N3",
                exampleJapanese: "予定を確認してください。",
                exampleChinese: "请确认日程。",
                tags: ["工作", "N3"],
                referenceDate: referenceDate
            ),
            makeWord(
                japanese: "影響",
                kana: "えいきょう",
                chineseMeaning: "影响",
                partOfSpeech: "名词/サ变动词",
                jlptLevel: "N3",
                exampleJapanese: "天気は気分に影響します。",
                exampleChinese: "天气会影响心情。",
                tags: ["抽象", "N3"],
                referenceDate: referenceDate
            ),
            makeWord(
                japanese: "集中",
                kana: "しゅうちゅう",
                chineseMeaning: "集中",
                partOfSpeech: "名词/サ变动词",
                jlptLevel: "N3",
                exampleJapanese: "勉強に集中します。",
                exampleChinese: "专心学习。",
                tags: ["学习", "N3"],
                referenceDate: referenceDate
            ),
            makeWord(
                japanese: "増える",
                kana: "ふえる",
                chineseMeaning: "增加",
                partOfSpeech: "动词",
                jlptLevel: "N3",
                exampleJapanese: "覚えた言葉が増えました。",
                exampleChinese: "记住的词变多了。",
                tags: ["变化", "N3"],
                referenceDate: referenceDate
            )
        ]
    }

    private static func makeWord(
        japanese: String,
        kana: String,
        chineseMeaning: String,
        partOfSpeech: String,
        jlptLevel: String,
        exampleJapanese: String,
        exampleChinese: String,
        tags: [String],
        referenceDate: Date
    ) -> VocabularyWord {
        let word = VocabularyWord(
            japanese: japanese,
            kana: kana,
            chineseMeaning: chineseMeaning,
            partOfSpeech: partOfSpeech,
            jlptLevel: jlptLevel,
            exampleJapanese: exampleJapanese,
            exampleChinese: exampleChinese,
            tags: tags,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
        let progress = LearningProgress(
            state: .new,
            dueAt: referenceDate,
            createdAt: referenceDate,
            updatedAt: referenceDate,
            word: word
        )
        word.progress = progress
        return word
    }
}
