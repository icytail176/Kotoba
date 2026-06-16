//
//  AppSection.swift
//  Kotoba
//
//  Created by Codex on 2026/6/16.
//

import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case today
    case wordbook
    case statistics
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            "今日学习"
        case .wordbook:
            "单词本"
        case .statistics:
            "学习统计"
        case .settings:
            "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .today:
            "calendar.badge.clock"
        case .wordbook:
            "books.vertical"
        case .statistics:
            "chart.bar.xaxis"
        case .settings:
            "gearshape"
        }
    }
}
