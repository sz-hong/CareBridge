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

    struct AIChatResponsePayload: Codable, Equatable {
        let conversationID: String?
        let reply: String
        let tokensUsed: Int?

        private enum CodingKeys: String, CodingKey {
            case conversationID
            case reply
            case content
            case message
            case text
            case tokensUsed
            case id
        }

        private struct NestedMessage: Decodable {
            let content: String?
            let text: String?
        }

        init(from decoder: Decoder) throws {
            if let singleValue = try? decoder.singleValueContainer(),
               let text = try? singleValue.decode(String.self),
               !text.isEmpty {
                conversationID = nil
                reply = text
                tokensUsed = nil
                return
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            conversationID =
                (try? container.decodeIfPresent(String.self, forKey: .conversationID))
                ?? (try? container.decodeIfPresent(String.self, forKey: .id))
            tokensUsed = try? container.decodeIfPresent(Int.self, forKey: .tokensUsed)

            let directReply =
                (try? container.decodeIfPresent(String.self, forKey: .reply))
                ?? (try? container.decodeIfPresent(String.self, forKey: .content))
                ?? (try? container.decodeIfPresent(String.self, forKey: .message))
                ?? (try? container.decodeIfPresent(String.self, forKey: .text))
            let nestedReply: NestedMessage?
            if let decoded = try? container.decodeIfPresent(
                NestedMessage.self,
                forKey: .message
            ) {
                nestedReply = decoded
            } else {
                nestedReply = nil
            }
            let resolvedReply =
                directReply
                ?? nestedReply?.content
                ?? nestedReply?.text

            guard let resolvedReply, !resolvedReply.isEmpty else {
                throw DecodingError.keyNotFound(
                    CodingKeys.reply,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription:
                            "Expected AI response text in reply, content, "
                            + "message, or text."
                    )
                )
            }
            reply = resolvedReply
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(
                conversationID,
                forKey: .conversationID
            )
            try container.encode(reply, forKey: .reply)
            try container.encodeIfPresent(tokensUsed, forKey: .tokensUsed)
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

private extension Data {
    mutating func appendString(_ value: String) {
        append(Data(value.utf8))
    }
}

extension APIDataService {
    // MARK: - AI
    func sendAIMessage(content: String) async throws -> AIMessage {
        let response: AIChatResponsePayload = try await post(
            path: APIEndpoint.aiChat,
            body: ["message": content]
        )
        return AIMessage(
            id: response.conversationID ?? UUID().uuidString,
            content: response.reply,
            isUser: false,
            timestamp: Date()
        )
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

    func generateSubsidyForm(
        formType: String,
        templateFileName: String?,
        templateFileData: Data?
    ) async throws -> AISubsidyFormResponse {
        if let templateFileData {
            return try await postSubsidyFormMultipart(
                formType: formType,
                templateFileName: templateFileName ?? "form-template.txt",
                templateFileData: templateFileData,
                retried: false
            )
        }

        return try await post(
            path: APIEndpoint.aiSubsidyForm,
            body: SubsidyFormRequestBody(formType: formType)
        )
    }

    private func postSubsidyFormMultipart(
        formType: String,
        templateFileName: String,
        templateFileData: Data,
        retried: Bool
    ) async throws -> AISubsidyFormResponse {
        guard let url = URL(string: "\(baseURL)\(APIEndpoint.aiSubsidyForm)") else {
            throw URLError(.badURL)
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = Self.subsidyFormMultipartBody(
            formType: formType,
            fileName: templateFileName,
            fileData: templateFileData,
            boundary: boundary
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.emptyResponse
        }

        if http.statusCode == 401 && !retried && authToken != nil {
            if await refreshAccessToken() {
                return try await postSubsidyFormMultipart(
                    formType: formType,
                    templateFileName: templateFileName,
                    templateFileData: templateFileData,
                    retried: true
                )
            }
            authToken = nil
            KeychainService.clearAll()
            throw APIError.unauthorized
        }

        guard 200...299 ~= http.statusCode else {
            throw APIError.serverError(statusCode: http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let apiResponse = try decoder.decode(APIResponse<AISubsidyFormResponse>.self, from: data)
        guard let result = apiResponse.data else {
            throw APIError.emptyResponse
        }
        return result
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
            case .error(let message):
                continuation.yield(.error(message))
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

    static func subsidyFormMultipartBody(
        formType: String,
        fileName: String,
        fileData: Data,
        boundary: String
    ) -> Data {
        var body = Data()
        appendMultipartField(name: "form_type", value: formType, to: &body, boundary: boundary)
        appendMultipartFile(
            name: "template_file",
            fileName: fileName,
            fileData: fileData,
            mimeType: subsidyTemplateMimeType(fileName: fileName),
            to: &body,
            boundary: boundary
        )
        body.appendString("--\(boundary)--\r\n")
        return body
    }

    private static func appendMultipartField(
        name: String,
        value: String,
        to body: inout Data,
        boundary: String
    ) {
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.appendString("\(value)\r\n")
    }

    private static func appendMultipartFile(
        name: String,
        fileName: String,
        fileData: Data,
        mimeType: String,
        to body: inout Data,
        boundary: String
    ) {
        body.appendString("--\(boundary)\r\n")
        body.appendString(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n"
        )
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.appendString("\r\n")
    }

    private static func subsidyTemplateMimeType(fileName: String) -> String {
        let lowercasedName = fileName.lowercased()
        if lowercasedName.hasSuffix(".json") {
            return "application/json"
        }
        return "text/plain"
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
        case "error":
            let message = json["message"] as? String ?? "AI 服務暫時無法使用，請稍後再試。"
            return .error(message)
        default:
            return .ignore
        }
    }
}
