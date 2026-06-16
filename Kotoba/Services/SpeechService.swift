//
//  SpeechService.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import AVFAudio
import Foundation

enum SpeechPlaybackState: Equatable {
    case idle
    case speakingWord
    case speakingExample

    var isSpeaking: Bool {
        self != .idle
    }

    var displayText: String {
        switch self {
        case .idle:
            return "未朗读"
        case .speakingWord:
            return "正在朗读单词"
        case .speakingExample:
            return "正在朗读例句"
        }
    }
}

@MainActor
protocol SpeechServicing: AnyObject {
    var state: SpeechPlaybackState { get }
    var speechRate: Float { get set }
    var onStateChange: ((SpeechPlaybackState) -> Void)? { get set }

    func speakWord(_ text: String)
    func speakExample(_ text: String)
    func stop()
}

@MainActor
final class SpeechService: NSObject, SpeechServicing {
    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var storedSpeechRate = Float(AppSettings.defaultJapaneseSpeechRate)

    var speechRate: Float {
        get {
            storedSpeechRate
        }
        set {
            storedSpeechRate = AppSettings.clampedJapaneseSpeechRate(newValue)
        }
    }

    private(set) var state: SpeechPlaybackState = .idle {
        didSet {
            guard oldValue != state else {
                return
            }

            onStateChange?(state)
        }
    }

    var onStateChange: ((SpeechPlaybackState) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speakWord(_ text: String) {
        speak(text, state: .speakingWord)
    }

    func speakExample(_ text: String) {
        speak(text, state: .speakingExample)
    }

    func stop() {
        guard state.isSpeaking || synthesizer.isSpeaking || synthesizer.isPaused else {
            return
        }

        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        state = .idle
    }

    private func speak(_ text: String, state newState: SpeechPlaybackState) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        if state.isSpeaking || synthesizer.isSpeaking || synthesizer.isPaused {
            currentUtterance = nil
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmedText)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = clampedUtteranceRate(speechRate)
        currentUtterance = utterance
        state = newState
        synthesizer.speak(utterance)
    }

    private func clampedUtteranceRate(_ rate: Float) -> Float {
        let appRate = AppSettings.clampedJapaneseSpeechRate(rate)
        return min(max(appRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }
}

extension SpeechService: @preconcurrency AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard utterance === currentUtterance else {
            return
        }

        currentUtterance = nil
        state = .idle
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard utterance === currentUtterance else {
            return
        }

        currentUtterance = nil
        state = .idle
    }
}
