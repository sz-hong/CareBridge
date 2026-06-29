import Foundation
import Testing
@testable import CareBridge

struct RequestTranslationDisplayTests {
    @Test func purchaseRequestFallsBackToServerLocalizedNoteText() throws {
        let json = """
        {
          "id": "purchase-1",
          "category": "daily",
          "status": "pending",
          "items": [{"name": "Sarung tangan", "quantity": "1"}],
          "requester": {"name": "Caregiver"},
          "created_at": "2026-06-29T08:00:00Z",
          "note": "Tolong beli sarung tangan",
          "note_translated": "請幫忙買手套"
        }
        """
        let request = try makeDecoder().decode(PurchaseRequest.self, from: Data(json.utf8))

        #expect(request.displayNotes(language: "zh-TW") == "請幫忙買手套")
    }

    @Test func leaveRequestFallsBackToServerLocalizedReasonText() throws {
        let json = """
        {
          "id": "leave-1",
          "type": "personal",
          "reason": "Saya perlu pulang kampung",
          "reason_translated": "我需要返鄉",
          "status": "pending",
          "start_date": "2026-06-29",
          "end_date": "2026-06-30",
          "applicant_name": "Caregiver",
          "votes": []
        }
        """
        let request = try makeDecoder().decode(LeaveRequest.self, from: Data(json.utf8))

        #expect(request.displayReason(language: "zh-TW") == "我需要返鄉")
    }
}

private func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}
