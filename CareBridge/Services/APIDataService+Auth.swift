import Foundation

extension APIDataService {
    /// Biometric login: exchange the stored refresh token for a fresh access
    /// token, then fetch the user profile. Throws if no refresh token is
    /// stored (user has never logged in on this device) or the refresh call
    /// fails (refresh token expired or revoked).
    func loginWithStoredRefreshToken() async throws -> UserProfile {
        guard KeychainService.refreshToken != nil else {
            throw APIError.unauthorized
        }
        let ok = await refreshAccessToken()
        guard ok else { throw APIError.unauthorized }
        return try await fetchProfile()
    }

    // MARK: - Auth
    func register(name: String, email: String, password: String, phone: String?, language: String?) async throws -> AuthResponse {
        struct Req: Encodable {
            let name: String; let email: String; let password: String
            let phone: String?; let language: String?
        }
        let result: AuthResponse = try await post(
            path: APIEndpoint.authRegister,
            body: Req(name: name, email: email, password: password,
                      phone: phone, language: language)
        )
        authToken = result.tokens.access
        KeychainService.accessToken  = result.tokens.access
        KeychainService.refreshToken = result.tokens.refresh
        return result
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        // Clear stale tokens so login request is unauthenticated
        authToken = nil
        KeychainService.clearAll()
        let result: AuthResponse = try await post(path: APIEndpoint.authLogin, body: ["email": email, "password": password])
        authToken = result.tokens.access
        KeychainService.accessToken = result.tokens.access
        KeychainService.refreshToken = result.tokens.refresh
        return result
    }

    func joinFamily(inviteCode: String, role: UserRole) async throws -> AuthResponse {
        let result: AuthResponse = try await post(
            path: APIEndpoint.authJoinFamily,
            body: ["invite_code": inviteCode, "role": role.rawValue]
        )
        authToken = result.tokens.access
        KeychainService.accessToken = result.tokens.access
        KeychainService.refreshToken = result.tokens.refresh
        return result
    }

    func logout() async throws {
        let _: EmptyResponse = try await post(path: APIEndpoint.authLogout)
        authToken = nil
        KeychainService.clearAll()
    }
}
