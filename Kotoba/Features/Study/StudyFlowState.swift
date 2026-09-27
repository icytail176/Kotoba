//
//  StudyFlowState.swift
//  Kotoba
//
//  Created by Codex on 2026/6/18.
//

import Foundation

enum StudyFlowState: String, Equatable {
    case idle
    case loadingWords
    case flashcard
    case flashcardRetry
    case spellingExpression
    case spellingReading
    case emptyQueue
    case summary
    case cancelled
    case error

    var title: String {
        switch self {
        case .idle:
            return "空闲"
        case .loadingWords:
            return "加载本组单词"
        case .flashcard:
            return "卡片学习"
        case .flashcardRetry:
            return "卡片错词重试"
        case .spellingExpression:
            return "第一轮 · 单词拼写"
        case .spellingReading:
            return "第二轮 · 假名拼写"
        case .emptyQueue:
            return "没有可学习的单词"
        case .summary:
            return "总结"
        case .cancelled:
            return "已取消"
        case .error:
            return "错误"
        }
    }
}
