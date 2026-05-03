import Foundation

extension APIDataService {
    // MARK: - Chat
    func fetchChatRooms() async throws -> [ChatRoom] { try await get(path: APIEndpoint.chats) }
    func fetchMessages(roomId: String) async throws -> [ChatMessage] { try await get(path: APIEndpoint.chatMessages(roomId: roomId)) }
    func sendMessage(roomId: String, content: String) async throws -> ChatMessage {
        try await post(path: APIEndpoint.chatMessages(roomId: roomId), body: ["type": "text", "content": content])
    }
    func sendRequestMessage(roomId: String, messageType: String, referenceId: String, content: String) async throws -> ChatMessage {
        try await post(path: APIEndpoint.chatMessages(roomId: roomId), body: [
            "type": messageType, "reference_id": referenceId, "content": content
        ])
    }
}
