//
//  LMStudioConjugationProvider.swift
//  Kotoba
//
//  Created by Codex on 2026/6/17.
//

import Foundation

struct LMStudioConjugationProvider: ConjugationGenerationProvider {
    private let baseURL: URL
    private let modelName: String
    private let timeout: TimeInterval
    private let session: URLSession
    private let validator = ConjugationValidationService()

    init(
        baseURL: URL,
        modelName: String,
        timeout: TimeInterval,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.modelName = modelName
        self.timeout = timeout
        self.session = session
    }

    func testConnection() async throws -> ProviderStatus {
        try validateLocalURL()
        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"

        let (_, response) = try await session.data(for: request)
        try validateHTTPResponse(response)
        return ProviderStatus(isAvailable: true, message: "LM Studio 连接正常")
    }

    func generateConjugations(
        requests: [ConjugationGenerationRequest]
    ) async throws -> [GeneratedConjugation] {
        try validateLocalURL()
        guard !requests.isEmpty else {
            return []
        }

        let payload = ChatCompletionRequest(
            model: modelName,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: try userPrompt(for: requests))
            ],
            temperature: 0.1,
            stream: false
        )

        var urlRequest = URLRequest(
            url: baseURL.appendingPathComponent("chat/completions"),
            timeoutInterval: timeout
        )
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: urlRequest)
        try validateHTTPResponse(response)

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConjugationProviderError.emptyContent
        }

        let cleanContent = stripCodeFence(from: content)
        guard let contentData = cleanContent.data(using: .utf8),
              let responsePayload = try? JSONDecoder().decode(ConjugationResponsePayload.self, from: contentData) else {
            throw ConjugationProviderError.decodingFailed
        }

        var requestsByID: [UUID: ConjugationGenerationRequest] = [:]
        for request in requests {
            requestsByID[request.wordID] = request
        }
        return responsePayload.items.map { item in
            let generated = GeneratedConjugation(
                wordID: item.wordID,
                expression: item.expression,
                reading: item.reading,
                conjugationClass: item.conjugationClass,
                forms: item.forms,
                source: .lmStudio,
                modelName: modelName
            )

            guard let request = requestsByID[item.wordID] else {
                return generated
            }

            let status = validator.validate(generated, for: request)
            if status == .invalid {
                return GeneratedConjugation(
                    wordID: generated.wordID,
                    expression: generated.expression,
                    reading: generated.reading,
                    conjugationClass: .unknown,
                    forms: generated.forms,
                    source: generated.source,
                    modelName: generated.modelName
                )
            }

            return generated
        }
    }

    private func validateLocalURL() throws {
        guard let host = baseURL.host?.lowercased(),
              ["localhost", "127.0.0.1", "::1"].contains(host) else {
            throw ConjugationProviderError.invalidLocalURL
        }
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConjugationProviderError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ConjugationProviderError.httpStatus(httpResponse.statusCode)
        }
    }

    private func userPrompt(for requests: [ConjugationGenerationRequest]) throws -> String {
        let data = try JSONEncoder().encode(requests)
        let json = String(data: data, encoding: .utf8) ?? "[]"
        return "为以下日语词生成可靠的活用 JSON。输入：\(json)"
    }

    private func stripCodeFence(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else {
            return trimmed
        }

        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        let bodyLines = lines.dropFirst().dropLast()
        return bodyLines.joined(separator: "\n")
    }

    private var systemPrompt: String {
        """
        你是日语活用生成器。只返回 JSON，不要解释。结构必须是：
        {"items":[{"wordID":"UUID","expression":"原词","reading":"假名","conjugationClass":"ichidanVerb|godanVerb|suruVerb|kuruVerb|iAdjective|naAdjective|none|unknown","forms":[{"type":"dictionary|polite|negative|past|teForm|connective","surface":"...","reading":"..."}]}]}
        每个词必须包含 dictionary 形式，surface/readings 不得为空。不能编造中文说明。
        """
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let stream: Bool
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}

private struct ConjugationResponsePayload: Decodable {
    let items: [ConjugationItem]
}

private struct ConjugationItem: Decodable {
    let wordID: UUID
    let expression: String
    let reading: String
    let conjugationClass: ConjugationClass
    let forms: [ConjugationForm]
}
