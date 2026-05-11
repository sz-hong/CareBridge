import Foundation
import Testing
@testable import CareBridge

struct APIDataServiceAITests {
    @Test func buildsAIStreamURLWithExplicitStreamQuery() throws {
        let url = try #require(
            APIDataService.aiStreamURL(baseURL: "https://api.carebridge-lab.com/api/v1")
        )

        #expect(url.absoluteString == "https://api.carebridge-lab.com/api/v1/ai/chat/?stream=true")
    }

    @Test func decodesBackendContentStreamEvents() {
        let event = APIDataService.decodeAIStreamEvent(
            line: #"data: {"type":"content","text":"收到，我會協助你。"}"#
        )

        #expect(event == .chunk("收到，我會協助你。"))
    }

    @Test func decodesLegacyTokenStreamEvents() {
        let event = APIDataService.decodeAIStreamEvent(
            line: #"data: {"type":"token","content":"legacy chunk"}"#
        )

        #expect(event == .chunk("legacy chunk"))
    }

    @Test func decodesDoneStreamEvent() {
        #expect(
            APIDataService.decodeAIStreamEvent(line: #"data: {"type":"done"}"#)
            == .done(conversationID: nil)
        )
    }

    @Test func decodesDoneStreamEventWithConversationID() {
        let event = APIDataService.decodeAIStreamEvent(
            line: #"data: {"type":"done","conversation_id":"conversation-123"}"#
        )

        #expect(event == .done(conversationID: "conversation-123"))
    }

    @Test func encodesAIChatRequestBodyWithConversationID() throws {
        let data = try APIDataService.aiChatRequestBody(
            prompt: "今天狀況如何？",
            conversationID: "conversation-123"
        )
        let payload = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )

        #expect(payload["message"] == "今天狀況如何？")
        #expect(payload["conversation_id"] == "conversation-123")
    }

    @Test func omitsConversationIDFromFirstAIChatRequestBody() throws {
        let data = try APIDataService.aiChatRequestBody(
            prompt: "今天狀況如何？",
            conversationID: nil
        )
        let payload = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )

        #expect(payload["message"] == "今天狀況如何？")
        #expect(payload["conversation_id"] == nil)
    }
}
