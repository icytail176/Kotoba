//
//  StudyCardView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import SwiftUI

struct StudyCardView: View {
    let item: StudySession.Item
    let progressText: String
    let isAnswerVisible: Bool
    let isSubmittingRating: Bool
    let speechState: SpeechPlaybackState
    let onShowAnswer: () -> Void
    let onToggleFavorite: () -> Void
    let onSpeakWord: () -> Void
    let onSpeakExample: () -> Void
    let onStopSpeech: () -> Void
    let onRate: (ReviewRating) -> Void

    private var word: VocabularyWord {
        item.word
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                Button(action: onShowAnswer) {
                    VStack(spacing: 22) {
                        Text(word.japanese)
                            .font(.system(size: 48, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.55)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity)

                        if isAnswerVisible {
                            answerContent
                        } else {
                            Text("按空格或点击卡片显示答案")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .padding(28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                )
                .keyboardShortcut(.space, modifiers: [])

                if isAnswerVisible {
                    ratingButtons
                }

                toolbar
            }
            .padding(24)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(progressText)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onToggleFavorite) {
                Label(word.isFavorite ? "取消收藏" : "收藏", systemImage: word.isFavorite ? "star.fill" : "star")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("f", modifiers: [])
            .help("收藏或取消收藏")
        }
    }

    private var answerContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudyAnswerRow(title: "假名", value: word.kana)
            StudyAnswerRow(title: "释义", value: word.chineseMeaning)
            StudyAnswerRow(title: "词性", value: word.partOfSpeech)
            StudyAnswerRow(title: "例句", value: word.exampleJapanese)
            StudyAnswerRow(title: "翻译", value: word.exampleChinese)
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var ratingButtons: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 12)], spacing: 12) {
            RatingButton(title: "忘记", key: "1", systemImage: "arrow.uturn.backward", tint: .red) {
                onRate(.again)
            }
            .keyboardShortcut("1", modifiers: [])
            .disabled(isSubmittingRating)

            RatingButton(title: "模糊", key: "2", systemImage: "questionmark.circle", tint: .orange) {
                onRate(.hard)
            }
            .keyboardShortcut("2", modifiers: [])
            .disabled(isSubmittingRating)

            RatingButton(title: "认识", key: "3", systemImage: "checkmark.circle", tint: .green) {
                onRate(.good)
            }
            .keyboardShortcut("3", modifiers: [])
            .disabled(isSubmittingRating)

            RatingButton(title: "熟练", key: "4", systemImage: "bolt.circle", tint: .blue) {
                onRate(.easy)
            }
            .keyboardShortcut("4", modifiers: [])
            .disabled(isSubmittingRating)
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if speechState.isSpeaking {
                Text(speechState.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                Button(action: onSpeakWord) {
                    Label(
                        speechState == .speakingWord ? "单词朗读中" : "朗读单词",
                        systemImage: speechState == .speakingWord ? "speaker.wave.3.fill" : "speaker.wave.2"
                    )
                }
                .keyboardShortcut("r", modifiers: [])

                Button(action: onSpeakExample) {
                    Label(
                        speechState == .speakingExample ? "例句朗读中" : "朗读例句",
                        systemImage: speechState == .speakingExample ? "text.bubble.fill" : "text.bubble"
                    )
                }
                .keyboardShortcut("e", modifiers: [])
                .disabled(word.exampleJapanese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(action: onStopSpeech) {
                    Label("停止朗读", systemImage: "stop.circle")
                }
                .keyboardShortcut("s", modifiers: [])
                .disabled(!speechState.isSpeaking)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StudyAnswerRow: View {
    let title: String
    let value: String

    var body: some View {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedValue.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(trimmedValue)
                    .font(.title3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct RatingButton: View {
    let title: String
    let key: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                Spacer(minLength: 6)
                Text(key)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }
}

#Preview {
    let word = SampleVocabularyWords.makeWords().first ?? VocabularyWord(
        japanese: "学生",
        kana: "がくせい",
        chineseMeaning: "学生",
        jlptLevel: "N5"
    )

    StudyCardView(
        item: StudySession.Item(id: word.id, word: word, kind: .newWord, dueAt: Date()),
        progressText: "1 / 10",
        isAnswerVisible: true,
        isSubmittingRating: false,
        speechState: .idle,
        onShowAnswer: {},
        onToggleFavorite: {},
        onSpeakWord: {},
        onSpeakExample: {},
        onStopSpeech: {},
        onRate: { _ in }
    )
    .frame(width: 760, height: 620)
}
