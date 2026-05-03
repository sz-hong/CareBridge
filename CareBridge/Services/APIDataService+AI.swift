import Foundation

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
        guard let url = URL(string: "\(baseURL)\(APIEndpoint.aiChat)") else {
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
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }

            if type == "done" {
                break
            }
            if type == "token", let token = json["content"] as? String {
                continuation.yield(token)
            }
        }
    }
}
