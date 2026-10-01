import SwiftData
import SwiftUI

struct StudyView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.studyGroupNewWordCountKey) private var storedStudyGroupNewWordCount = AppSettings.defaultStudyGroupNewWordCount
    @AppStorage(AppSettings.reviewGroupWordCountKey) private var storedReviewGroupWordCount = AppSettings.defaultReviewGroupWordCount
    @StateObject private var viewModel = StudySessionViewModel()
    @State private var didConfirmCompletion = false

    let wordBookID: UUID?
    let mode: StudySession.Mode
    let completedTitle: String
    let completedMessage: String
    let studyGroupNewWordCount: Int?
    let reviewGroupWordCount: Int?
    let onSessionCompleted: () -> Void
    let onSessionCancelled: () -> Void

    init(
        wordBookID: UUID? = nil,
        mode: StudySession.Mode = .mixed,
        completedTitle: String = "今日学习已完成",
        completedMessage: String = "当前没有到期复习，也没有需要加入队列的新词。",
        studyGroupNewWordCount: Int? = nil,
        reviewGroupWordCount: Int? = nil,
        onSessionCompleted: @escaping () -> Void = {},
        onSessionCancelled: @escaping () -> Void = {}
    ) {
        self.wordBookID = wordBookID
        self.mode = mode
        self.completedTitle = completedTitle
        self.completedMessage = completedMessage
        self.studyGroupNewWordCount = studyGroupNewWordCount
        self.reviewGroupWordCount = reviewGroupWordCount
        self.onSessionCompleted = onSessionCompleted
        self.onSessionCancelled = onSessionCancelled
    }

    var body: some View {
        Group {
            if let summary = viewModel.summary {
                StudySummaryView(summary: summary) {
                    didConfirmCompletion = true
                    onSessionCompleted()
                }
            } else if viewModel.hasRecoverableRatingSaveFailure {
                VStack(spacing: 16) {
                    EmptyStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "评价保存失败",
                        message: viewModel.errorMessage ?? "评价尚未保存，可以重试或返回当前卡片。"
                    )
                    HStack {
                        Button("重试保存") { viewModel.retrySavingRating(context: modelContext) }
                            .buttonStyle(.borderedProminent)
                        Button("返回卡片") { viewModel.cancelRatingSaveFailure() }
                            .buttonStyle(.bordered)
                    }
                }
            } else if viewModel.hasRecoverableSpellingSaveFailure {
                VStack(spacing: 16) {
                    EmptyStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "拼写记录保存失败",
                        message: viewModel.errorMessage ?? "学习进度已保存，但拼写记录尚未保存。"
                    )
                    HStack {
                        Button("重试保存") { viewModel.retrySavingSpelling(context: modelContext) }
                            .buttonStyle(.borderedProminent)
                        Button("继续完成") { viewModel.continueAfterSpellingSaveFailure() }
                            .buttonStyle(.bordered)
                    }
                }
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "学习队列加载失败", message: errorMessage)
            } else if viewModel.isSpellingActive {
                SpellingView(
                    expressionQuestions: viewModel.expressionSpellingQuestions,
                    readingQuestions: viewModel.readingSpellingQuestions,
                    onPhaseChanged: { viewModel.spellingPhaseChanged($0) },
                    onComplete: { viewModel.completeSpelling($0, context: modelContext) }
                )
            } else if let item = viewModel.currentItem {
                StudyCardView(
                    item: item,
                    progressText: viewModel.progressText,
                    isAnswerVisible: viewModel.isAnswerVisible,
                    isSubmittingRating: viewModel.isSubmittingRating,
                    conjugation: viewModel.currentConjugation,
                    onShowAnswer: { viewModel.showAnswer() },
                    onToggleFavorite: { viewModel.handleShortcut(.toggleFavorite, context: modelContext) },
                    onRate: { viewModel.handleShortcut(.rate($0), context: modelContext) }
                )
            } else {
                EmptyStateView(systemImage: "checkmark.circle", title: completedTitle, message: completedMessage)
            }
        }
        .task(id: taskIdentity) {
            if viewModel.session == nil {
                viewModel.loadSession(
                    context: modelContext,
                    wordBookID: wordBookID,
                    mode: mode,
                    studyGroupNewWordCount: clampedStudyGroupNewWordCount,
                    reviewGroupWordCount: clampedReviewGroupWordCount,
                    randomizesQueue: true
                )
            }
        }
        .onDisappear {
            guard !didConfirmCompletion else { return }
            viewModel.cancelSession()
            onSessionCancelled()
        }
    }

    private var clampedStudyGroupNewWordCount: Int {
        AppSettings.clampedStudyGroupNewWordCount(studyGroupNewWordCount ?? storedStudyGroupNewWordCount)
    }

    private var clampedReviewGroupWordCount: Int {
        AppSettings.clampedReviewGroupWordCount(reviewGroupWordCount ?? storedReviewGroupWordCount)
    }

    private var taskIdentity: String {
        "\(wordBookID?.uuidString ?? "all")-\(mode.rawValue)"
    }
}

#Preview {
    StudyView()
        .modelContainer(PreviewModelContainer.make())
        .frame(width: 760, height: 620)
}
