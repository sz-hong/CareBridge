import Foundation

extension APIDataService {
    enum AIStreamEvent: Equatable {
        case chunk(String)
        case done
        case ignore
    }
}

extension APIDataService {
    // MARK: - AI
    func sendAIMessage(content: String) async throws -> AIMessage {
        try await post(path: APIEndpoint.aiChat, body: ["message": content])
    }

    func streamAIResponse(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await streamAIResponse(
                        prompt: prompt,
                        retried: false,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func streamAIResponse(
        prompt: String,
        retried: Bool,
        continuation: AsyncThrowingStream<String, Error>.Continuation
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
        request.httpBody = try JSONEncoder().encode(["message": prompt])

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.emptyResponse
        }

        if http.statusCode == 401 && !retried && authToken != nil {
            if await refreshAccessToken() {
                try await streamAIResponse(
                    prompt: prompt,
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
                continuation.yield(text)
            case .done:
                break
            case .ignore:
                continue
            }
        }
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

    static func decodeAIStreamEvent(line: String) -> AIStreamEvent {
        guard line.hasPrefix("data: ") else { return .ignore }

        let payload = String(line.dropFirst(6))
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return .ignore
        }

        switch type {
        case "done":
            return .done
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
