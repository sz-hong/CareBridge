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
