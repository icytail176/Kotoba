//
//  SpeechServiceTests.swift
//  KotobaTests
//
//  Created by Codex on 2026/6/16.
//

import XCTest

@MainActor
final class SpeechServiceTests: XCTestCase {
    func testEmptyStringsAreIgnored() {
        let service = SpeechService()

        service.speakWord("   ")
        service.speakExample("\n\t")

        XCTAssertEqual(service.state, .idle)
    }

    func testNewSpeechRequestReplacesCurrentVisibleState() {
        let service = SpeechService()

        service.speakWord("学生")
        XCTAssertEqual(service.state, .speakingWord)

        service.speakExample("私は学生です。")
        XCTAssertEqual(service.state, .speakingExample)

        service.stop()
        XCTAssertEqual(service.state, .idle)
    }

    func testSpeechRateIsClampedToSettingsRange() {
        let service = SpeechService()

        service.speechRate = 99
        XCTAssertEqual(service.speechRate, Float(AppSettings.maximumJapaneseSpeechRate))

        service.speechRate = -1
        XCTAssertEqual(service.speechRate, Float(AppSettings.minimumJapaneseSpeechRate))
    }
}
