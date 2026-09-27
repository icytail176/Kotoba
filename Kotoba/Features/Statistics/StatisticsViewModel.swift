//
//  StatisticsViewModel.swift
//  Kotoba
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

    func load(context: ModelContext, calendar: Calendar, now: Date = Date()) {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil

        let service = service
        let calculator = calculator
        let container = context.container

        loadTask = Task { [weak self, service, calculator, container, calendar, now] in
            do {
                // Cumulative counts and streaks must always use the complete history.
                let snapshot = try await service.makeSnapshot(in: container)
                guard !Task.isCancelled else { return }

                let statistics = await Task.detached(priority: .userInitiated) {
                    calculator.calculate(input: snapshot.input, calendar: calendar, now: now)
                }.value
                guard !Task.isCancelled else { return }

                self?.statistics = statistics
                self?.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self?.statistics = nil
                self?.isLoading = false
                self?.errorMessage = "无法加载学习统计：\(error.localizedDescription)"
            }
        }
    }
}
