import Foundation

extension APIDataService {
    // MARK: - AI
    func sendAIMessage(content: String) async throws -> AIMessage {
        try await post(path: APIEndpoint.aiChat, body: ["message": content])
    }
}
