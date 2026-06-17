//
//  SpellingView.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import SwiftUI

struct SpellingView: View {
    @StateObject private var viewModel: SpellingSessionViewModel
    @FocusState private var isInputFocused: Bool
    let autoSpeakAnswer: Bool
    let speechState: SpeechPlaybackState
    let onSpeakAnswer: (String) -> Void
    let onSpeakExample: (String) -> Void
    let onStopSpeech: () -> Void
    let onComplete: (SpellingSessionViewModel.Summary) -> Void

    init(
        words: [VocabularyWord],
        conjugationRecords: [ConjugationRecord] = [],
        autoSpeakAnswer: Bool,
        speechState: SpeechPlaybackState,
        onSpeakAnswer: @escaping (String) -> Void,
        onSpeakExample: @escaping (String) -> Void,
        onStopSpeech: @escaping () -> Void,
        onComplete: @escaping (SpellingSessionViewModel.Summary) -> Void
    ) {
        let questions = SpellingQuestionGenerator().generate(
            words: words,
            conjugationRecords: conjugationRecords
        )
        _viewModel = StateObject(wrappedValue: SpellingSessionViewModel(questions: questions))
        self.autoSpeakAnswer = autoSpeakAnswer
        self.speechState = speechState
        self.onSpeakAnswer = onSpeakAnswer
        self.onSpeakExample = onSpeakExample
        self.onStopSpeech = onStopSpeech
        self.onComplete = onComplete
    }

    var body: some View {
        Group {
            if let question = viewModel.currentQuestion {
                questionContent(question)
            } else {
                EmptyStateView(
                    systemImage: "square.and.pencil",
                    title: "拼写巩固已完成",
                    message: "本组没有可生成的拼写题。"
                )
            }
        }
        .onChange(of: viewModel.summary) {
            if let summary = viewModel.summary {
                onComplete(summary)
            }
        }
    }

    private func questionContent(_ question: SpellingQuestion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(question)
                promptCard(question)
                answerInput(question)
                feedbackView(question)
                actionButtons(question)
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .task {
            isInputFocused = true
        }
    }

    private func header(_ question: SpellingQuestion) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.progressText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(question.formType?.title ?? question.direction.title)
                    .font(.title3.weight(.semibold))
            }

            Spacer()

            if viewModel.isRetryRound {
                Text("错题")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.14), in: Capsule())
            }
        }
    }

    private func promptCard(_ question: SpellingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(promptTitle(for: question))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(question.prompt)
                .font(.system(size: 38, weight: .semibold))
                .minimumScaleFactor(0.6)
                .lineLimit(3)
                .textSelection(.enabled)

            if !question.referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(question.referenceText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        }
    }

    private func answerInput(_ question: SpellingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("答案")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField(answerPlaceholder(for: question), text: $viewModel.answer)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused($isInputFocused)
                .disabled(viewModel.isAnswerLocked)
                .onSubmit {
                    submitCurrentAnswer()
                }
        }
    }

    @ViewBuilder
    private func feedbackView(_ question: SpellingQuestion) -> some View {
        if let feedback = viewModel.feedback {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    feedback == .correct ? "正确" : "需要重练",
                    systemImage: feedback == .correct ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundStyle(feedback == .correct ? .green : .red)
                .font(.headline)

                LabeledContent("正确答案") {
                    Text(question.expectedAnswer)
                        .textSelection(.enabled)
                }

                LabeledContent("假名") {
                    Text(question.direction == .expressionToReading ? question.expectedAnswer : question.wordReading)
                        .textSelection(.enabled)
                }

                LabeledContent("词典形") {
                    Text("\(question.wordExpression)（\(question.wordReading)）")
                        .textSelection(.enabled)
                }

                if let formType = question.formType {
                    LabeledContent("活用形式") {
                        Text(formType.title)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func actionButtons(_ question: SpellingQuestion) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                submitOrNextButton
                speechButtons(question)
            }

            VStack(alignment: .leading, spacing: 10) {
                submitOrNextButton
                speechButtons(question)
            }
        }
    }

    private var submitOrNextButton: some View {
        Button {
            if viewModel.isAnswerLocked {
                viewModel.advance()
                isInputFocused = true
            } else {
                submitCurrentAnswer()
            }
        } label: {
            Label(viewModel.isAnswerLocked ? "下一题" : "提交答案", systemImage: viewModel.isAnswerLocked ? "arrow.right" : "checkmark")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.isAnswerLocked && !viewModel.canSubmit)
    }

    private func speechButtons(_ question: SpellingQuestion) -> some View {
        HStack(spacing: 8) {
            Button {
                onSpeakAnswer(question.expectedAnswer)
            } label: {
                Label(speechState.isSpeaking ? "重新朗读" : "朗读答案", systemImage: "speaker.wave.2")
            }
            .keyboardShortcutIf(!isInputFocused && viewModel.isAnswerLocked, "r", modifiers: [])
            .disabled(!viewModel.isAnswerLocked)

            Button {
                onSpeakExample(question.exampleJapanese)
            } label: {
                Label("朗读例句", systemImage: "text.bubble")
            }
            .keyboardShortcutIf(!isInputFocused && viewModel.isAnswerLocked, "e", modifiers: [])
            .disabled(!viewModel.isAnswerLocked || question.exampleJapanese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                onStopSpeech()
            } label: {
                Label("停止朗读", systemImage: "stop.circle")
            }
            .keyboardShortcutIf(!isInputFocused, "s", modifiers: [])
            .disabled(!speechState.isSpeaking)
        }
        .buttonStyle(.bordered)
    }

    private func submitCurrentAnswer() {
        guard let question = viewModel.currentQuestion,
              viewModel.submitAnswer() else {
            return
        }

        isInputFocused = false
        if autoSpeakAnswer {
            onSpeakAnswer(question.expectedAnswer)
        }
    }

    private func promptTitle(for question: SpellingQuestion) -> String {
        switch question.direction {
        case .meaningToExpression:
            return "根据中文写日语"
        case .readingToExpression:
            return question.formType == nil ? "根据假名写单词" : "根据活用读音写形式"
        case .expressionToReading:
            return question.formType == nil ? "根据单词写假名" : "根据活用形式写读音"
        }
    }

    private func answerPlaceholder(for question: SpellingQuestion) -> String {
        question.direction == .expressionToReading ? "输入假名" : "输入完整日语词形"
    }
}

#Preview {
    let words = SampleVocabularyWords.makeWords()
    SpellingView(
        words: Array(words.prefix(3)),
        autoSpeakAnswer: true,
        speechState: .idle,
        onSpeakAnswer: { _ in },
        onSpeakExample: { _ in },
        onStopSpeech: {},
        onComplete: { _ in }
    )
    .frame(width: 760, height: 620)
}
