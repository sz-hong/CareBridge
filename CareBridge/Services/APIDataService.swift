import Foundation

protocol AuthTokenStoring: AnyObject {
    var accessToken: String? { get set }
    var refreshToken: String? { get set }
    func clearAll()
}

final class KeychainAuthTokenStore: AuthTokenStoring {
    var accessToken: String? {
        get { KeychainService.accessToken }
        set { KeychainService.accessToken = newValue }
    }

    var refreshToken: String? {
        get { KeychainService.refreshToken }
        set { KeychainService.refreshToken = newValue }
    }

    func clearAll() {
        KeychainService.clearAll()
    }
}

extension Notification.Name {
    static let careBridgeAuthenticationExpired = Notification.Name("careBridgeAuthenticationExpired")
}

actor AccessTokenRefreshGate {
    private var isRefreshing = false
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    func waitForRefreshTurn() async -> Bool? {
        if isRefreshing {
            return await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        isRefreshing = true
        return nil
    }

    func finishRefresh(_ result: Bool) {
        let pendingWaiters = waiters
        waiters.removeAll()
        isRefreshing = false
        for waiter in pendingWaiters {
            waiter.resume(returning: result)
        }
    }
}

/// Real API implementation connects to backend REST API via JSON.
class APIDataService: DataService {
    static let sharedRefreshGate = AccessTokenRefreshGate()

    let baseURL: String
    var authToken: String?
    let apiClient: APIClient
    let session: APIHTTPSession
    let tokenStore: AuthTokenStoring
    let privacyRedactionService: PrivacyRedactionServicing
    private let refreshGate: AccessTokenRefreshGate

    init(
        baseURL: String = AppConfig.apiBaseURL,
        session: APIHTTPSession = URLSession.shared,
        tokenStore: AuthTokenStoring = KeychainAuthTokenStore(),
        refreshGate: AccessTokenRefreshGate = APIDataService.sharedRefreshGate,
        privacyRedactionService: PrivacyRedactionServicing = DefaultPrivacyRedactionService()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenStore = tokenStore
        self.refreshGate = refreshGate
        self.apiClient = APIClient(baseURL: baseURL, session: session)
        self.authToken = tokenStore.accessToken
        self.privacyRedactionService = privacyRedactionService
    }

    // MARK: - Generic Request Helpers

    func request<T: Codable>(
        _ method: String,
        path: String,
        body: (any Encodable)? = nil,
        retried: Bool = false
    ) async throws -> T {
        do {
            return try await apiClient.request(
                method,
                path: path,
                body: body,
                authToken: authToken
            )
        } catch APIError.serverError(let statusCode) where statusCode == 401 && !retried && authToken != nil {
            if await refreshAccessToken() {
                return try await request(method, path: path, body: body, retried: true)
            }
            throw APIError.serverError(statusCode: 401)
        } catch APIError.backendError(let statusCode, _) where statusCode == 401 && !retried && authToken != nil {
            if await refreshAccessToken() {
                return try await request(method, path: path, body: body, retried: true)
            }
            throw APIError.serverError(statusCode: 401)
        }
    }

    func requestPage<T: Codable>(
        _ method: String,
        path: String,
        retried: Bool = false
    ) async throws -> PaginatedResult<T> {
        do {
            return try await apiClient.requestPage(
                method,
                path: path,
                authToken: authToken
            )
        } catch APIError.serverError(let statusCode)
            where statusCode == 401 && !retried && authToken != nil {
            if await refreshAccessToken() {
                return try await requestPage(
                    method,
                    path: path,
                    retried: true
                )
            }
            throw APIError.serverError(statusCode: 401)
        } catch APIError.backendError(let statusCode, _)
            where statusCode == 401 && !retried && authToken != nil {
            if await refreshAccessToken() {
                return try await requestPage(
                    method,
                    path: path,
                    retried: true
                )
            }
            throw APIError.serverError(statusCode: 401)
        }
    }

    /// Exchange refresh token for a new access token (SimpleJWT, rotation enabled).
    /// Response format is `{access, refresh}` without the `{success,data}` envelope.
    func refreshAccessToken() async -> Bool {
        if let sharedResult = await refreshGate.waitForRefreshTurn() {
            return applyRefreshResult(sharedResult)
        }

        let refreshed = await performRefreshAccessToken()
        await refreshGate.finishRefresh(refreshed)
        return applyRefreshResult(refreshed)
    }

    private func applyRefreshResult(_ refreshed: Bool) -> Bool {
        if refreshed {
            authToken = tokenStore.accessToken
        } else if authToken != nil || tokenStore.accessToken != nil || tokenStore.refreshToken != nil {
            expireAuthentication()
        }
        return refreshed
    }

    private func performRefreshAccessToken() async -> Bool {
        guard let refresh = tokenStore.refreshToken,
              let url = URL(string: "\(baseURL)\(APIEndpoint.tokenRefresh)") else {
            return false
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh": refresh])

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccess = obj["access"] as? String else {
                return false
            }
            authToken = newAccess
            tokenStore.accessToken = newAccess
            if let newRefresh = obj["refresh"] as? String {
                tokenStore.refreshToken = newRefresh
            }
            return true
        } catch {
            return false
        }
    }

    func expireAuthentication() {
        authToken = nil
        tokenStore.clearAll()
        let postNotification = {
            NotificationCenter.default.post(name: .careBridgeAuthenticationExpired, object: nil)
        }
        if Thread.isMainThread {
            postNotification()
        } else {
            DispatchQueue.main.async(execute: postNotification)
        }
    }

    func get<T: Codable>(path: String) async throws -> T {
        try await request("GET", path: path)
    }

    func post<T: Codable>(path: String, body: (any Encodable)? = nil) async throws -> T {
        try await request("POST", path: path, body: body)
    }

    func put<T: Codable>(path: String, body: (any Encodable)? = nil) async throws -> T {
        try await request("PUT", path: path, body: body)
    }

    func patch<T: Codable>(path: String, body: (any Encodable)? = nil) async throws -> T {
        try await request("PATCH", path: path, body: body)
    }

    func delete(path: String) async throws {
        let _: EmptyResponse = try await request("DELETE", path: path)
    }
}
// MARK: - Helpers
enum APIError: LocalizedError {
    case serverError(statusCode: Int)
    case backendError(statusCode: Int, message: String)
    case emptyResponse
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .serverError(let code):          return "伺服器錯誤 (\(code))"
        case .backendError(_, let message):   return message
        case .emptyResponse:                  return "伺服器回傳空資料"
        case .unauthorized:                   return "未授權，請重新登入"
        }
    }
}

struct EmptyResponse: Codable {}
