//
//  StatisticsViewModel.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Combine
import Foundation
import SwiftData

@MainActor
final class StatisticsViewModel: ObservableObject {
    @Published private(set) var statistics: StudyStatistics?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service: StudyStatisticsService
    private let calculator: StudyStatisticsCalculator
    private var loadTask: Task<Void, Never>?

    init(
        service: StudyStatisticsService? = nil,
        calculator: StudyStatisticsCalculator? = nil
    ) {
        self.service = service ?? StudyStatisticsService()
        self.calculator = calculator ?? StudyStatisticsCalculator()
    }

    func load(
        context: ModelContext,
        calendar: Calendar,
        now: Date = Date()
    ) {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil

        do {
            let input = try service.makeInput(in: context)
            let calculator = calculator
            loadTask = Task { [weak self, input, calculator, calendar, now] in
                let statistics = await Task.detached(priority: .userInitiated) {
                    calculator.calculate(input: input, calendar: calendar, now: now)
                }.value

                guard !Task.isCancelled else {
                    return
                }

                self?.statistics = statistics
                self?.isLoading = false
            }
        } catch {
            statistics = nil
            isLoading = false
            errorMessage = "无法加载学习统计：\(error.localizedDescription)"
        }
    }
}
