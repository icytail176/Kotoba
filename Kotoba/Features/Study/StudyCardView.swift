import AppKit
import SwiftUI

struct StudyCardView: View {
    let item: StudySession.Item
    let progressText: String
    let isAnswerVisible: Bool
    let isSubmittingRating: Bool
    let conjugation: GeneratedConjugation?
    let onShowAnswer: () -> Void
    let onToggleFavorite: () -> Void
    let onRate: (ReviewRating) -> Void

    @State private var currentPage = 0

    private var word: VocabularyWord { item.word }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    card
                }
                .padding(24)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }

            if isAnswerVisible {
                Divider()
                ratingButtons
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .background(.bar)
            }
        }
        .onChange(of: word.id) { currentPage = 0 }
        .onChange(of: isAnswerVisible) { _, isVisible in
            if !isVisible {
                currentPage = 0
            }
        }
        .background {
            StudyKeyboardEventMonitor { command in
                handleKeyboardCommand(command)
            }
            .frame(width: 0, height: 0)
        }
    }

    @ViewBuilder
    private var card: some View {
        if isAnswerVisible {
            VStack(spacing: 22) {
                expression
                if currentPage == 0 {
                    answerContent
                } else {
                    conjugationPage
                }
            }
            .studyCardSurface()

            if hasConjugationPage {
                pageControls
            }
        } else {
            Button(action: onShowAnswer) {
                VStack(spacing: 22) {
                    expression
                    Text("按空格或点击卡片显示答案")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .studyCardSurface()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    private var expression: some View {
        Text(word.japanese)
            .font(.system(size: 48, weight: .semibold))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.55)
            .lineLimit(3)
            .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(progressText)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            if !word.jlptLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(word.jlptLevel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
            Button(action: onToggleFavorite) {
                Label(word.isFavorite ? "取消收藏" : "收藏", systemImage: word.isFavorite ? "star.fill" : "star")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("f", modifiers: [])
            .help(word.isFavorite ? "取消收藏（F）" : "收藏（F）")
            .accessibilityLabel(word.isFavorite ? "取消收藏" : "收藏")
            .accessibilityHint("快捷键 F")
        }
    }

    private var answerContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudyAnswerRow(title: "假名", value: word.kana)
            StudyAnswerRow(title: "释义", value: word.chineseMeaning)
            StudyAnswerRow(title: "词性", value: word.partOfSpeech)
            if let etymology = LoanwordEtymologyPresentation.make(for: word) {
                StudyAnswerRow(title: etymology.title, value: etymology.value)
            }
            StudyAnswerRow(title: "例句", value: word.exampleJapanese)
            StudyAnswerRow(title: "翻译", value: word.exampleChinese)
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var conjugationPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("活用")
                .font(.headline)
            ConjugationFormsListView(forms: conjugationForms, columnCount: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    private var conjugationForms: [ConjugationForm] {
        StudyCardContent.conjugationForms(from: conjugation)
    }

    private var hasConjugationPage: Bool {
        !conjugationForms.isEmpty
    }

    private var pageControls: some View {
        HStack(spacing: 12) {
            Button {
                showPreviousPage()
            } label: {
                Label("上一页", systemImage: "chevron.left")
            }
            .disabled(currentPage == 0)

            Text("第 \(currentPage + 1) / 2 页")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 78)

            Button {
                showNextPage()
            } label: {
                Label("下一页", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(currentPage == 1)
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("学习卡片分页")
    }

    private var ratingButtons: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                RatingButton(title: "忘记", key: "1", systemImage: "arrow.uturn.backward", tint: .red) { onRate(.again) }
                RatingButton(title: "模糊", key: "2", systemImage: "questionmark.circle", tint: .orange) { onRate(.hard) }
                RatingButton(title: "认识", key: "3", systemImage: "checkmark.circle", tint: .green) { onRate(.good) }
            }
            .disabled(isSubmittingRating)

            Divider().frame(height: 52)

            RatingButton(title: "熟练", key: "⌫", systemImage: "bolt.circle", tint: .blue) { onRate(.easy) }
                .frame(maxWidth: 180)
                .disabled(isSubmittingRating)
                .help("熟练（Delete / Backspace）")
        }
    }

    private func handleKeyboardCommand(_ command: StudyCardKeyboardCommand) -> Bool {
        switch command {
        case .showAnswer:
            if !isAnswerVisible {
                onShowAnswer()
            }
        case .previousPage:
            if isAnswerVisible, hasConjugationPage {
                showPreviousPage()
            }
        case .nextPage:
            if isAnswerVisible, hasConjugationPage {
                showNextPage()
            }
        case .rate(let rating):
            if isAnswerVisible, !isSubmittingRating {
                onRate(rating)
            }
        }
        return true
    }

    private func showPreviousPage() {
        currentPage = max(0, currentPage - 1)
    }

    private func showNextPage() {
        guard hasConjugationPage else { return }
        currentPage = min(1, currentPage + 1)
    }

}

enum StudyCardKeyboardCommand: Equatable {
    case showAnswer
    case previousPage
    case nextPage
    case rate(ReviewRating)

    nonisolated static func command(forKeyCode keyCode: UInt16, characters: String?) -> Self? {
        switch keyCode {
        case 18: return .rate(.again)
        case 19: return .rate(.hard)
        case 20: return .rate(.good)
        case 49: return .showAnswer
        case 51: return .rate(.easy)
        case 123: return .previousPage
        case 124: return .nextPage
        default:
            guard let characters else { return nil }
            return command(for: characters)
        }
    }

    nonisolated static func command(for key: KeyEquivalent, characters: String) -> Self? {
        if key == .delete {
            return .rate(.easy)
        }
        if key == .leftArrow {
            return .previousPage
        }
        if key == .rightArrow {
            return .nextPage
        }
        return command(for: characters)
    }

    nonisolated static func command(for characters: String) -> Self? {
        switch characters {
        case " ": .showAnswer
        case "1": .rate(.again)
        case "2": .rate(.hard)
        case "3": .rate(.good)
        case "\u{7F}", "\u{8}": .rate(.easy)
        case "\u{F702}": .previousPage
        case "\u{F703}": .nextPage
        default: nil
        }
    }
}

private struct StudyKeyboardEventMonitor: NSViewRepresentable {
    let onCommand: (StudyCardKeyboardCommand) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onCommand: onCommand)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.start(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onCommand = onCommand
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onCommand: (StudyCardKeyboardCommand) -> Bool
        private weak var hostView: NSView?
        private var monitor: Any?

        init(onCommand: @escaping (StudyCardKeyboardCommand) -> Bool) {
            self.onCommand = onCommand
        }

        func start(for view: NSView) {
            hostView = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      event.window === hostView?.window,
                      StudyKeyboardEventPolicy.shouldHandle(
                        isRepeat: event.isARepeat,
                        modifiers: event.modifierFlags,
                        firstResponder: event.window?.firstResponder
                      ),
                      let command = StudyCardKeyboardCommand.command(
                        forKeyCode: event.keyCode,
                        characters: event.charactersIgnoringModifiers
                      ) else {
                    return event
                }

                return onCommand(command) ? nil : event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            stop()
        }
    }
}

enum StudyKeyboardEventPolicy {
    nonisolated static func shouldHandle(
        isRepeat: Bool,
        modifiers: NSEvent.ModifierFlags,
        firstResponder: NSResponder?
    ) -> Bool {
        guard !isRepeat,
              modifiers.intersection([.command, .control, .option, .shift]).isEmpty else {
            return false
        }

        return !(firstResponder is NSTextView) && !(firstResponder is NSTextField)
    }
}

enum StudyCardContent {
    static func conjugationForms(from conjugation: GeneratedConjugation?) -> [ConjugationForm] {
        guard let conjugation, conjugation.conjugationClass != .none else {
            return []
        }
        return conjugation.forms.filter { $0.type != .dictionary }
    }

    static func pageCount(for conjugation: GeneratedConjugation?) -> Int {
        conjugationForms(from: conjugation).isEmpty ? 1 : 2
    }
}

private extension View {
    func studyCardSurface() -> some View {
        frame(maxWidth: .infinity, minHeight: 280)
            .padding(28)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1) }
    }
}

private struct StudyAnswerRow: View {
    let title: String
    let value: String

    var body: some View {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedValue.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(trimmedValue).font(.title3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
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
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                    Text(title)
                    Spacer(minLength: 0)
                    shortcutBadge
                }

                VStack(spacing: 5) {
                    Image(systemName: systemImage)
                    Text(title)
                    shortcutBadge
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 72)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(tint.opacity(isHovering ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(isHovering ? 0.75 : 0.42), lineWidth: 1.2) }
        .onHover { isHovering = $0 }
        .help("\(title)（\(key)）")
    }

    private var shortcutBadge: some View {
        Text(key)
            .font(.callout.monospacedDigit().weight(.semibold))
            .foregroundStyle(tint)
            .frame(minWidth: 28, minHeight: 28)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
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
        conjugation: ConjugationEngine().generate(for: word),
        onShowAnswer: {},
        onToggleFavorite: {},
        onRate: { _ in }
    )
    .frame(width: 760, height: 620)
}
