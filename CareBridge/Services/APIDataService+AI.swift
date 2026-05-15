import Foundation

extension APIDataService {
    struct AIChatRequestBody: Encodable {
        let message: String
        let conversationID: String?

        enum CodingKeys: String, CodingKey {
            case message
            case conversationID = "conversation_id"
        }
    }

    struct FirstAidQueryRequestBody: Encodable {
        let query: String
    }

    struct CareAnalysisRequestBody: Encodable {
        let days: Int
    }

    struct HandoverReportRequestBody: Encodable {
        let date: String
    }

    struct SubsidyFormRequestBody: Encodable {
        let formType: String

        enum CodingKeys: String, CodingKey {
            case formType = "form_type"
        }
    }
}

extension APIDataService {
    // MARK: - AI
    func sendAIMessage(content: String) async throws -> AIMessage {
        try await post(path: APIEndpoint.aiChat, body: ["message": content])
    }

    func fetchCareAnalysis(days: Int) async throws -> AICareAnalysisResponse {
        try await post(
            path: APIEndpoint.aiCareAnalysis,
            body: CareAnalysisRequestBody(days: days)
        )
    }

    func generateHandoverReport(date: String) async throws -> AIHandoverReportResponse {
        try await post(
            path: APIEndpoint.aiHandoverReport,
            body: HandoverReportRequestBody(date: date)
        )
    }

    func generateSubsidyForm(formType: String) async throws -> AISubsidyFormResponse {
        try await post(
            path: APIEndpoint.aiSubsidyForm,
            body: SubsidyFormRequestBody(formType: formType)
        )
    }

    func streamAIResponse(
        prompt: String,
        conversationID: String?
    ) -> AsyncThrowingStream<AIResponseStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await streamAIResponse(
                        prompt: prompt,
                        conversationID: conversationID,
                        retried: false,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func streamAIResponse(
        prompt: String,
        conversationID: String?,
        retried: Bool,
        continuation: AsyncThrowingStream<AIResponseStreamEvent, Error>.Continuation
    ) async throws {
        guard let url = Self.aiStreamURL(baseURL: baseURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try Self.aiChatRequestBody(
            prompt: prompt,
            conversationID: conversationID
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.emptyResponse
        }

        if http.statusCode == 401 && !retried && authToken != nil {
            if await refreshAccessToken() {
                try await streamAIResponse(
                    prompt: prompt,
                    conversationID: conversationID,
                    retried: true,
                    continuation: continuation
                )
                return
            }
            authToken = nil
            KeychainService.clearAll()
            throw APIError.unauthorized
        }

        guard 200...299 ~= http.statusCode else {
            throw APIError.serverError(statusCode: http.statusCode)
        }

        for try await line in bytes.lines {
            switch Self.decodeAIStreamEvent(line: line) {
            case .chunk(let text):
                continuation.yield(.chunk(text))
            case .done(let conversationID):
                continuation.yield(.done(conversationID: conversationID))
            case .ignore:
                continue
            }
        }
    }

    static func aiChatRequestBody(
        prompt: String,
        conversationID: String?
    ) throws -> Data {
        try JSONEncoder().encode(
            AIChatRequestBody(
                message: prompt,
                conversationID: conversationID
            )
        )
    }

    static func firstAidQueryRequestBody(query: String) throws -> Data {
        try JSONEncoder().encode(FirstAidQueryRequestBody(query: query))
    }

    static func careAnalysisRequestBody(days: Int) throws -> Data {
        try JSONEncoder().encode(CareAnalysisRequestBody(days: days))
    }

    static func handoverReportRequestBody(date: String) throws -> Data {
        try JSONEncoder().encode(HandoverReportRequestBody(date: date))
    }

    static func subsidyFormRequestBody(formType: String) throws -> Data {
        try JSONEncoder().encode(SubsidyFormRequestBody(formType: formType))
    }

    static func aiStreamURL(baseURL: String) -> URL? {
        guard var components = URLComponents(string: "\(baseURL)\(APIEndpoint.aiChat)") else {
            return nil
        }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "stream", value: "true"))
        components.queryItems = queryItems
        return components.url
    }

    static func decodeAIStreamEvent(line: String) -> AIResponseStreamEvent {
        guard line.hasPrefix("data: ") else { return .ignore }

        let payload = String(line.dropFirst(6))
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return .ignore
        }

        switch type {
        case "done":
            return .done(conversationID: json["conversation_id"] as? String)
        case "content":
            if let text = json["text"] as? String {
                return .chunk(text)
            }
            if let content = json["content"] as? String {
                return .chunk(content)
            }
            return .ignore
        case "token":
            if let content = json["content"] as? String {
                return .chunk(content)
            }
            if let text = json["text"] as? String {
                return .chunk(text)
            }
            return .ignore
        default:
            return .ignore
        }
    }
}
