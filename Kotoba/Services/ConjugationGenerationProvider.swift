//
//  ConjugationGenerationProvider.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Foundation

protocol ConjugationGenerationProvider {
    func testConnection() async throws -> ProviderStatus
    func generateConjugations(
        requests: [ConjugationGenerationRequest]
    ) async throws -> [GeneratedConjugation]
}

enum ConjugationProviderError: LocalizedError, Equatable {
    case invalidLocalURL
    case invalidResponse
    case httpStatus(Int)
    case emptyContent
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidLocalURL:
            return "当前版本只允许连接 localhost、127.0.0.1 或 ::1。"
        case .invalidResponse:
            return "LM Studio 返回了无法识别的响应。"
        case .httpStatus(let status):
            return "LM Studio 返回 HTTP \(status)。"
        case .emptyContent:
            return "LM Studio 没有返回内容。"
        case .decodingFailed:
            return "LM Studio 返回的活用 JSON 无法解析。"
        }
    }
}
