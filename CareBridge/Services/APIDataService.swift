import Foundation

/// Real API implementation — connects to backend REST API via JSON.
/// Replace `baseURL` with your actual server address.
class APIDataService: DataService {

    let baseURL: String
    var authToken: String?
    let apiClient: APIClient
    let privacyRedactionService: PrivacyRedactionServicing

    init(
        baseURL: String = AppConfig.apiBaseURL,
        privacyRedactionService: PrivacyRedactionServicing = DefaultPrivacyRedactionService()
    ) {
        self.baseURL = baseURL
        self.apiClient = APIClient(baseURL: baseURL)
        self.authToken = KeychainService.accessToken
        self.privacyRedactionService = privacyRedactionService
    }

    // MARK: - Generic Request Helpers

    func request<T: Codable>(_ method: String, path: String, body: (any Encodable)? = nil, retried: Bool = false) async throws -> T {
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
            authToken = nil
            KeychainService.clearAll()
            throw APIError.serverError(statusCode: 401)
        } catch APIError.backendError(let statusCode, _) where statusCode == 401 && !retried && authToken != nil {
            if await refreshAccessToken() {
                return try await request(method, path: path, body: body, retried: true)
            }
            authToken = nil
            KeychainService.clearAll()
            throw APIError.serverError(statusCode: 401)
        }
    }

    /// Exchange refresh token for a new access token (SimpleJWT, rotation enabled).
    /// Response format is `{access, refresh}` without the `{success,data}` envelope.
    func refreshAccessToken() async -> Bool {
        guard let refresh = KeychainService.refreshToken,
              let url = URL(string: "\(baseURL)\(APIEndpoint.tokenRefresh)") else { return false }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh": refresh])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccess = obj["access"] as? String else {
                return false
            }
            authToken = newAccess
            KeychainService.accessToken = newAccess
            if let newRefresh = obj["refresh"] as? String {
                KeychainService.refreshToken = newRefresh
            }
            return true
        } catch {
            return false
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
