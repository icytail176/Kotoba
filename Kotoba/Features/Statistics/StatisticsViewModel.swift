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
    @Published private(set) var selectedRange: StatisticsTimeRange = .sevenDays
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service: StudyStatisticsService
    private let calculator: StudyStatisticsCalculator
    private var loadTask: Task<Void, Never>?
    private var cachedInput: StudyStatisticsInput?
    private var cachedCalendar: Calendar?
    private var cachedNow: Date?

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
        let selectedRange = selectedRange

        loadTask = Task { [weak self, service, calculator, container, calendar, now, selectedRange] in
            do {
                // Cumulative counts and streaks must always use the complete history.
                let snapshot = try await service.makeSnapshot(in: container)
                guard !Task.isCancelled else { return }
                let activeRange = self?.selectedRange ?? selectedRange

                let statistics = await Task.detached(priority: .userInitiated) {
                    calculator.calculate(
                        input: snapshot.input,
                        calendar: calendar,
                        now: now,
                        range: activeRange
                    )
                }.value
                guard !Task.isCancelled else { return }

                self?.cachedInput = snapshot.input
                self?.cachedCalendar = calendar
                self?.cachedNow = now
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

    func selectRange(_ range: StatisticsTimeRange) {
        guard selectedRange != range else { return }
        selectedRange = range
        guard let cachedInput, let cachedCalendar, let cachedNow else { return }

        statistics = calculator.calculate(
            input: cachedInput,
            calendar: cachedCalendar,
            now: cachedNow,
            range: range
        )
    }
}
