import Foundation
import Testing
@testable import CareBridge

private final class InMemoryAuthTokenStore: AuthTokenStoring {
    var accessToken: String?
    var refreshToken: String?

    init(accessToken: String?, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    func clearAll() {
        accessToken = nil
        refreshToken = nil
    }
}

private final class ControlledRefreshSession: APIHTTPSession, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<(Data, URLResponse), Error>] = []
    private(set) var requests: [URLRequest] = []

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            requests.append(request)
            continuations.append(continuation)
            lock.unlock()
        }
    }

    func complete(json: String, statusCode: Int = 200) {
        lock.lock()
        let pending = continuations
        continuations.removeAll()
        let url = requests.last?.url ?? URL(string: "https://example.com")!
        lock.unlock()

        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        for continuation in pending {
            continuation.resume(returning: (Data(json.utf8), response))
        }
    }
}

private final class NotificationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var didReceive = false

    var received: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didReceive
    }

    func markReceived() {
        lock.lock()
        didReceive = true
        lock.unlock()
    }
}

struct APIDataServiceAuthTests {
    @Test func concurrentRefreshCallsShareOneNetworkRequest() async throws {
        let session = ControlledRefreshSession()
        let tokenStore = InMemoryAuthTokenStore(
            accessToken: "expired-access",
            refreshToken: "refresh-token"
        )
        let service = APIDataService(
            baseURL: "https://example.com/api/v1",
            session: session,
            tokenStore: tokenStore,
            refreshGate: AccessTokenRefreshGate()
        )

        async let first = service.refreshAccessToken()
        async let second = service.refreshAccessToken()
        async let third = service.refreshAccessToken()

        for _ in 0..<100 where session.requestCount == 0 {
            await Task.yield()
        }
        #expect(session.requestCount == 1)

        session.complete(json: #"{"access":"fresh-access","refresh":"fresh-refresh"}"#)
        let results = await [first, second, third]

        #expect(results == [true, true, true])
        #expect(session.requestCount == 1)
        #expect(service.authToken == "fresh-access")
        #expect(tokenStore.accessToken == "fresh-access")
        #expect(tokenStore.refreshToken == "fresh-refresh")
    }

    @MainActor
    @Test func expireAuthenticationClearsTokensAndPostsNotification() async {
        let tokenStore = InMemoryAuthTokenStore(
            accessToken: "expired-access",
            refreshToken: "refresh-token"
        )
        let service = APIDataService(
            baseURL: "https://example.com/api/v1",
            tokenStore: tokenStore,
            refreshGate: AccessTokenRefreshGate()
        )
        let notificationProbe = NotificationProbe()
        let observer = NotificationCenter.default.addObserver(
            forName: .careBridgeAuthenticationExpired,
            object: nil,
            queue: nil
        ) { _ in
            notificationProbe.markReceived()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        service.expireAuthentication()

        #expect(notificationProbe.received)
        #expect(service.authToken == nil)
        #expect(tokenStore.accessToken == nil)
        #expect(tokenStore.refreshToken == nil)
    }
}