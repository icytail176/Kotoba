import AppKit
import SwiftUI

struct SpellingView: View {
    @StateObject private var viewModel: SpellingSessionViewModel
    @State private var isInputFocused = false
    @State private var inputHint: String?
    let onPhaseChanged: (SpellingSessionViewModel.Phase) -> Void
    let onComplete: (SpellingSessionViewModel.Summary) -> Void

    init(
        expressionQuestions: [SpellingQuestion],
        readingQuestions: [SpellingQuestion],
        onPhaseChanged: @escaping (SpellingSessionViewModel.Phase) -> Void = { _ in },
        onComplete: @escaping (SpellingSessionViewModel.Summary) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: SpellingSessionViewModel(
                expressionQuestions: expressionQuestions,
                readingQuestions: readingQuestions
            )
        )
        self.onPhaseChanged = onPhaseChanged
        self.onComplete = onComplete
    }

    var body: some View {
        Group {
            if let question = viewModel.currentQuestion {
                questionContent(question)
            } else {
                EmptyStateView(systemImage: "square.and.pencil", title: "拼写巩固已完成", message: "本组没有可生成的拼写题。")
            }
        }
        .background {
            SpellingHintKeyboardMonitor(phase: viewModel.phase) {
                viewModel.revealHint()
            }
            .frame(width: 0, height: 0)
        }
        .task { onPhaseChanged(viewModel.phase) }
        .onChange(of: viewModel.phase) { _, phase in onPhaseChanged(phase) }
        .onChange(of: viewModel.summary) {
            if let summary = viewModel.summary { onComplete(summary) }
        }
        .onDisappear { isInputFocused = false }
    }

    private func questionContent(_ question: SpellingQuestion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                promptCard(question)
                answerInput(question)
                feedbackView(question)
                submitOrNextButton
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .task { focusInput() }
        .onChange(of: question.id) { focusInput() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.phase == .expression ? "第一轮 · 单词拼写" : "第二轮 · 假名拼写")
                    .font(.title3.weight(.semibold))
                Text(viewModel.progressText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.isRetryAppearance {
                Text("重练")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.14), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private func promptCard(_ question: SpellingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.phase == .expression {
                Text("根据释义和语境写出完整日语单词")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(question.meaningChinese)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if question.hasExampleContext {
                    Divider()
                    Text(question.contextText)
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                    if !question.exampleChinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(question.exampleChinese)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                hintControl(question)
            } else {
                Text("看汉字词写假名")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(question.wordExpression)
                    .font(.system(size: 36, weight: .semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(3)
                    .textSelection(.enabled)
                if !question.meaningChinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(question.meaningChinese)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1) }
    }

    @ViewBuilder
    private func hintControl(_ question: SpellingQuestion) -> some View {
        Divider()
        if viewModel.isHintVisible {
            LabeledContent("假名提示") {
                Text(question.wordReading).textSelection(.enabled)
            }
        } else {
            Button {
                _ = viewModel.revealHint()
            } label: {
                Label("提示  ⌘⇧H", systemImage: "lightbulb")
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canRevealHint)
            .help("显示假名；使用提示后，本词会在本轮稍后重新测试")
        }
    }

    private func answerInput(_ question: SpellingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("答案").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            IMEAwareTextField(
                text: $viewModel.answer,
                isFocused: $isInputFocused,
                placeholder: question.direction == .expressionToReading ? "输入假名" : "输入日语单词",
                isEnabled: !viewModel.isAnswerLocked,
                onSubmit: { performPrimaryAction(isMarkedTextActive: $0) }
            )
            .frame(height: 30)
            if let inputHint { Text(inputHint).font(.caption).foregroundStyle(.orange) }
        }
    }

    @ViewBuilder
    private func feedbackView(_ question: SpellingQuestion) -> some View {
        if let feedback = viewModel.feedback {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    feedback == .correct ? "正确" : "拼写错误，请重新输入",
                    systemImage: feedback == .correct ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundStyle(feedback == .correct ? .green : .red)
                .font(.headline)
                LabeledContent("你的答案") { Text(viewModel.answer).textSelection(.enabled) }
                if feedback == .incorrect {
                    LabeledContent("正确答案") { Text(question.expectedAnswer).textSelection(.enabled) }
                    Text(question.direction == .expressionToReading ? "请重新输入这个词的假名。" : "请重新输入词条中的完整词典形。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if feedback == .correct && viewModel.currentCorrectAnswerWasRequeued {
                    Text("本次已纠正；该词已加入本轮队尾，稍后将再次测试。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var submitOrNextButton: some View {
        Button { performPrimaryAction(isMarkedTextActive: false) } label: {
            Label(viewModel.primaryActionTitle, systemImage: viewModel.isAnswerLocked ? "arrow.right" : "checkmark")
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcutIf(viewModel.isAnswerLocked, .return, modifiers: [])
        .disabled(!viewModel.isAnswerLocked && !viewModel.canSubmit)
    }

    private func performPrimaryAction(isMarkedTextActive: Bool) {
        switch viewModel.questionState {
        case .answering:
            guard !isMarkedTextActive else { return }
            guard viewModel.canSubmit else {
                if viewModel.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { inputHint = "请输入答案" }
                return
            }
            guard viewModel.handleEnter() == .submitted else { return }
            inputHint = nil
            viewModel.isAnswerLocked ? (isInputFocused = false) : focusInput()
        case .submitted:
            _ = viewModel.handleEnter()
            inputHint = nil
            viewModel.currentQuestion == nil ? (isInputFocused = false) : focusInput()
        }
    }

    private func focusInput() {
        guard !viewModel.isAnswerLocked else { isInputFocused = false; return }
        DispatchQueue.main.async { isInputFocused = true }
    }
}

enum SpellingHintShortcutPolicy {
    static func shouldHandle(
        phase: SpellingSessionViewModel.Phase,
        isRepeat: Bool,
        modifiers: NSEvent.ModifierFlags,
        keyCode: UInt16,
        characters: String?,
        hasMarkedText: Bool
    ) -> Bool {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        return phase == .expression
            && !isRepeat
            && !hasMarkedText
            && flags == [.command, .shift]
            && (keyCode == 4 || characters?.lowercased() == "h")
    }
}

private struct SpellingHintKeyboardMonitor: NSViewRepresentable {
    let phase: SpellingSessionViewModel.Phase
    let onHint: () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(phase: phase, onHint: onHint) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.start(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.phase = phase
        context.coordinator.onHint = onHint
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.stop() }

    final class Coordinator {
        var phase: SpellingSessionViewModel.Phase
        var onHint: () -> Bool
        private weak var hostView: NSView?
        private var monitor: Any?

        init(phase: SpellingSessionViewModel.Phase, onHint: @escaping () -> Bool) {
            self.phase = phase
            self.onHint = onHint
        }

        func start(for view: NSView) {
            hostView = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === hostView?.window else { return event }
                let markedText = (event.window?.firstResponder as? NSTextView)?.hasMarkedText() ?? false
                guard SpellingHintShortcutPolicy.shouldHandle(
                    phase: phase,
                    isRepeat: event.isARepeat,
                    modifiers: event.modifierFlags,
                    keyCode: event.keyCode,
                    characters: event.charactersIgnoringModifiers,
                    hasMarkedText: markedText
                ) else { return event }
                return onHint() ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }

        deinit { stop() }
    }
}

#Preview {
    let words = Array(SampleVocabularyWords.makeWords().prefix(3))
    let generator = SpellingQuestionGenerator()
    SpellingView(
        expressionQuestions: generator.generateExpressionQuestions(words: words),
        readingQuestions: generator.generateReadingQuestions(words: words),
        onComplete: { _ in }
    )
        .frame(width: 760, height: 620)
}
