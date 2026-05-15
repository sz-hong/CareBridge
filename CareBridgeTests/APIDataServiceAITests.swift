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
        let message = "\u{6536}\u{5230}\u{FF0C}\u{6211}\u{6703}\u{5354}\u{52A9}\u{4F60}\u{3002}"
        let event = APIDataService.decodeAIStreamEvent(
            line: #"data: {"type":"content","text":"\u6536\u5230\uff0c\u6211\u6703\u5354\u52a9\u4f60\u3002"}"#
        )

        #expect(event == .chunk(message))
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
        let prompt = "\u{4ECA}\u{5929}\u{72C0}\u{6CC1}\u{5982}\u{4F55}\u{FF1F}"
        let data = try APIDataService.aiChatRequestBody(
            prompt: prompt,
            conversationID: "conversation-123"
        )
        let payload = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )

        #expect(payload["message"] == prompt)
        #expect(payload["conversation_id"] == "conversation-123")
    }

    @Test func omitsConversationIDFromFirstAIChatRequestBody() throws {
        let prompt = "\u{4ECA}\u{5929}\u{72C0}\u{6CC1}\u{5982}\u{4F55}\u{FF1F}"
        let data = try APIDataService.aiChatRequestBody(
            prompt: prompt,
            conversationID: nil
        )
        let payload = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )

        #expect(payload["message"] == prompt)
        #expect(payload["conversation_id"] == nil)
    }

    @Test func encodesFirstAidQueryRequestBody() throws {
        let data = try APIDataService.firstAidQueryRequestBody(query: "chest pain")
        let payload = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )

        #expect(payload["query"] == "chest pain")
    }

    @Test func encodesAIReportRequestBodies() throws {
        let analysis = try #require(
            JSONSerialization.jsonObject(
                with: APIDataService.careAnalysisRequestBody(days: 14)
            ) as? [String: Int]
        )
        let handover = try #require(
            JSONSerialization.jsonObject(
                with: APIDataService.handoverReportRequestBody(date: "2026-05-15")
            ) as? [String: String]
        )
        let subsidy = try #require(
            JSONSerialization.jsonObject(
                with: APIDataService.subsidyFormRequestBody(formType: "long_term_care")
            ) as? [String: String]
        )

        #expect(analysis["days"] == 14)
        #expect(handover["date"] == "2026-05-15")
        #expect(subsidy["form_type"] == "long_term_care")
    }

    @Test func decodesAIReportAndSubsidyResponses() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let care = try decoder.decode(
            AICareAnalysisResponse.self,
            from: Data(#"{"analysis":"care summary","period_days":7,"tokens_used":12}"#.utf8)
        )
        let handover = try decoder.decode(
            AIHandoverReportResponse.self,
            from: Data(#"{"report":"handover report","date":"2026-05-15","tokens_used":20}"#.utf8)
        )
        let subsidy = try decoder.decode(
            AISubsidyFormResponse.self,
            from: Data(#"{"form_type":"long_term_care","form_fields":{"applicant":"Grandma Wu","days":30},"tokens_used":30}"#.utf8)
        )

        #expect(care.analysis == "care summary")
        #expect(care.periodDays == 7)
        #expect(handover.report == "handover report")
        #expect(handover.date == "2026-05-15")
        #expect(subsidy.formFields["applicant"] == "Grandma Wu")
        #expect(subsidy.formFields["days"] == "30")
    }

    @Test func dynamicTranslationDisplayFallsBackToOriginal() {
        #expect(
            DynamicTranslation.displayText(
                original: "Minum obat pagi",
                translations: ["en": "Morning medication is done"],
                language: "en"
            ) == "Morning medication is done"
        )
        #expect(
            DynamicTranslation.displayText(
                original: "Minum obat pagi",
                translations: ["en": "Morning medication is done"],
                language: "vi"
            ) == "Minum obat pagi"
        )
    }
}
