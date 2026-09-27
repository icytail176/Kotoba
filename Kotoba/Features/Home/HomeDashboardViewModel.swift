//
//  HomeDashboardViewModel.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Combine
import Foundation
import SwiftData

@MainActor
final class HomeDashboardViewModel: ObservableObject {
    @Published private(set) var snapshot = HomeDashboardSnapshot(
        wordBookID: nil,
        wordBookName: "",
        wordBookDescription: "",
        totalWordCount: 0,
        remainingNewWordCount: 0,
        dueReviewCount: 0,
        masteredWordCount: 0,
        hasWordBooks: false,
        example: nil
    )
    @Published private(set) var wordBooks: [WordBook] = []
    @Published var errorMessage: String?

    private let dashboardService: HomeDashboardService
    private let wordBookService: WordBookService

    init(
        dashboardService: HomeDashboardService? = nil,
        wordBookService: WordBookService? = nil
    ) {
        self.dashboardService = dashboardService ?? HomeDashboardService()
        self.wordBookService = wordBookService ?? WordBookService()
    }

    var canStartLearning: Bool {
        snapshot.wordBookID != nil && snapshot.remainingNewWordCount > 0
    }

    var canStartReview: Bool {
        snapshot.wordBookID != nil && snapshot.dueReviewCount > 0
    }

    func load(
        context: ModelContext,
        selectedWordBookID: String,
        updateSelectedWordBookID: (String) -> Void
    ) {
        do {
            try PerformanceTrace.measure("Home view model load") {
                let result = try dashboardService.makeSnapshot(
                    in: context,
                    selectedIDString: selectedWordBookID.isEmpty ? nil : selectedWordBookID
                )
                wordBooks = result.wordBooks
                snapshot = result.snapshot

                if let resolvedID = result.resolvedWordBook?.id.uuidString,
                   resolvedID != selectedWordBookID {
                    updateSelectedWordBookID(resolvedID)
                } else if result.resolvedWordBook == nil, !selectedWordBookID.isEmpty {
                    updateSelectedWordBookID("")
                }

                errorMessage = nil
            }
        } catch {
            errorMessage = "首页数据加载失败：\(error.localizedDescription)"
        }
    }

    func refreshExample(context: ModelContext) {
        guard let wordBookID = snapshot.wordBookID else {
            return
        }

        do {
            try PerformanceTrace.measure("Home random example load") {
                let books = try wordBookService.fetchWordBooks(in: context)
                guard let book = books.first(where: { $0.id == wordBookID }) else {
                    return
                }

                snapshot = HomeDashboardSnapshot(
                    wordBookID: snapshot.wordBookID,
                    wordBookName: snapshot.wordBookName,
                    wordBookDescription: snapshot.wordBookDescription,
                    totalWordCount: snapshot.totalWordCount,
                    remainingNewWordCount: snapshot.remainingNewWordCount,
                    dueReviewCount: snapshot.dueReviewCount,
                    masteredWordCount: snapshot.masteredWordCount,
                    hasWordBooks: snapshot.hasWordBooks,
                    example: dashboardService.randomExample(from: book.words.filter { !$0.isArchived })
                )
                errorMessage = nil
            }
        } catch {
            errorMessage = "随机例句加载失败：\(error.localizedDescription)"
        }
    }
}
