import Foundation
import Testing
@testable import CareBridge

private struct TestPayload: Codable, Equatable {
    let value: String
}

private final class MockHTTPSession: APIHTTPSession {
    var responseData: Data
    var statusCode: Int
    private(set) var lastRequest: URLRequest?

    init(json: String, statusCode: Int = 200) {
        self.responseData = Data(json.utf8)
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}

struct APIClientTests {
    @Test func buildsCareLogDateEndpoint() {
        #expect(APIEndpoint.careLogs(on: "2026-05-02") == "/care-logs/?date=2026-05-02")
        #expect(APIEndpoint.document(id: "abc") == "/documents/abc/")
    }

    @Test func buildsDomainEndpoints() {
        #expect(APIEndpoint.authRegister == "/auth/register/")
        #expect(APIEndpoint.authLogin == "/auth/login/")
        #expect(APIEndpoint.authJoinFamily == "/auth/join-family/")
        #expect(APIEndpoint.authLogout == "/auth/logout/")
        #expect(APIEndpoint.authMe == "/auth/me/")
        #expect(APIEndpoint.families == "/families/")
        #expect(APIEndpoint.familyMembers == "/families/members/")
        #expect(APIEndpoint.healthDashboard == "/health-data/dashboard/")
        #expect(APIEndpoint.healthWeeklySteps == "/health-data/weekly-steps/")
        #expect(APIEndpoint.chats == "/chats/")
        #expect(APIEndpoint.chatMessages(roomId: "room-1") == "/chats/room-1/messages/")
        #expect(APIEndpoint.careLogUploadURL == "/care-logs/upload-url/")
        #expect(APIEndpoint.medications == "/medications/")
        #expect(APIEndpoint.medication(id: "med-1") == "/medications/med-1/")
        #expect(APIEndpoint.medicationTodayConfirmations == "/medications/today_confirmations/")
        #expect(APIEndpoint.medicationConfirm(id: "med-1") == "/medications/med-1/confirm/")
        #expect(APIEndpoint.expenses == "/expenses/")
        #expect(APIEndpoint.expense(id: "expense-1") == "/expenses/expense-1/")
        #expect(APIEndpoint.expenseMonthly == "/expenses/monthly/")
        #expect(APIEndpoint.expenseUploadURL == "/expenses/upload-url/")
        #expect(APIEndpoint.todos == "/todos/")
        #expect(APIEndpoint.todo(id: "todo-1") == "/todos/todo-1/")
        #expect(APIEndpoint.events == "/events/")
        #expect(APIEndpoint.eventBatch == "/events/batch/")
        #expect(APIEndpoint.leaves == "/leaves/")
        #expect(APIEndpoint.leaveStatus(id: "leave-1") == "/leaves/leave-1/status/")
        #expect(APIEndpoint.leaveVote(id: "leave-1") == "/leaves/leave-1/vote/")
        #expect(APIEndpoint.documents == "/documents/")
        #expect(APIEndpoint.documentUploadURL == "/documents/upload-url/")
        #expect(APIEndpoint.notifications == "/notifications/")
        #expect(APIEndpoint.notificationRead(id: "notif-1") == "/notifications/notif-1/read/")
        #expect(APIEndpoint.notificationDevice == "/notifications/device/")
        #expect(APIEndpoint.board == "/board/")
        #expect(APIEndpoint.boardStatus(id: "board-1") == "/board/board-1/status/")
        #expect(APIEndpoint.aiChat == "/ai/chat/")
        #expect(APIEndpoint.aiFirstAid == "/ai/first-aid/")
        #expect(APIEndpoint.aiFirstAidScenarios == "/ai/first-aid/scenarios/")
        #expect(APIEndpoint.aiCareAnalysis == "/ai/care-analysis/")
        #expect(APIEndpoint.aiHandoverReport == "/ai/handover-report/")
        #expect(APIEndpoint.aiSubsidyForm == "/ai/subsidy-form/")
        #expect(APIEndpoint.sosTrigger == "/sos/trigger/")
    }

    @Test func decodesSuccessEnvelopeData() async throws {
        let session = MockHTTPSession(
            json: #"{"success":true,"data":{"value":"decoded"}}"#
        )
        let client = APIClient(baseURL: "https://example.com", session: session)

        let result: TestPayload = try await client.request(
            "GET",
            path: "/care-logs/",
            authToken: "token"
        )

        #expect(result == TestPayload(value: "decoded"))
        #expect(session.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    }

    @Test func decodesPaginatedEnvelopeMetadata() async throws {
        let session = MockHTTPSession(
            json: """
            {
              "success": true,
              "data": [{"value": "first"}],
              "meta": {
                "count": 21,
                "next": "https://example.com/items/?page=2",
                "previous": null
              }
            }
            """
        )
        let client = APIClient(baseURL: "https://example.com", session: session)

        let result: PaginatedResult<TestPayload> = try await client.requestPage(
            "GET",
            path: "/care-logs/?page=1&page_size=20"
        )

        #expect(result.items == [TestPayload(value: "first")])
        #expect(result.totalCount == 21)
        #expect(result.hasNextPage)
    }

    @Test func buildsPaginatedCareLogEndpoint() {
        #expect(
            APIEndpoint.careLogs(
                date: "2026-06-22",
                type: .meal,
                page: 2
            )
            == "/care-logs/?date=2026-06-22&type=meal&page=2&page_size=20"
        )
    }

    @Test func decodesEmptySuccessEnvelope() async throws {
        let session = MockHTTPSession(json: #"{"success":true,"data":{}}"#)
        let client = APIClient(baseURL: "https://example.com", session: session)

        let _: EmptyResponse = try await client.request("DELETE", path: "/documents/1/")

        #expect(session.lastRequest?.httpMethod == "DELETE")
    }

    @Test func throwsBackendErrorMessageFromErrorEnvelope() async throws {
        let session = MockHTTPSession(
            json: #"{"success":false,"error":{"code":"INVALID","message":"Bad request"}}"#,
            statusCode: 400
        )
        let client = APIClient(baseURL: "https://example.com", session: session)

        do {
            let _: TestPayload = try await client.request("GET", path: "/broken/")
            Issue.record("Expected request to throw")
        } catch APIError.backendError(let statusCode, let message) {
            #expect(statusCode == 400)
            #expect(message == "Bad request")
        }
    }
}
