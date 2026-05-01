import Foundation
import UIKit

/// Real API implementation — connects to backend REST API via JSON.
/// Replace `baseURL` with your actual server address.
class APIDataService: DataService {

    private let baseURL: String
    private var authToken: String?
    private let apiClient: APIClient

    init(baseURL: String = AppConfig.apiBaseURL) {
        self.baseURL = baseURL
        self.apiClient = APIClient(baseURL: baseURL)
        self.authToken = KeychainService.accessToken
    }

    // MARK: - Generic Request Helpers

    private func request<T: Codable>(_ method: String, path: String, body: (any Encodable)? = nil, retried: Bool = false) async throws -> T {
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

    /// Exchange refresh token for a new access token (SimpleJWT, rotation enabled).
    /// Response format is `{access, refresh}` without the `{success,data}` envelope.
    private func refreshAccessToken() async -> Bool {
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

    private func get<T: Codable>(path: String) async throws -> T {
        try await request("GET", path: path)
    }

    private func post<T: Codable>(path: String, body: (any Encodable)? = nil) async throws -> T {
        try await request("POST", path: path, body: body)
    }

    private func put<T: Codable>(path: String, body: (any Encodable)? = nil) async throws -> T {
        try await request("PUT", path: path, body: body)
    }

    private func patch<T: Codable>(path: String, body: (any Encodable)? = nil) async throws -> T {
        try await request("PATCH", path: path, body: body)
    }

    private func delete(path: String) async throws {
        let _: EmptyResponse = try await request("DELETE", path: path)
    }

    // MARK: - Auth
    func register(name: String, email: String, password: String, phone: String?, language: String?) async throws -> AuthResponse {
        struct Req: Encodable {
            let name: String; let email: String; let password: String
            let phone: String?; let language: String?
        }
        let result: AuthResponse = try await post(
            path: "/auth/register/",
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
        let result: AuthResponse = try await post(path: "/auth/login/", body: ["email": email, "password": password])
        authToken = result.tokens.access
        KeychainService.accessToken = result.tokens.access
        KeychainService.refreshToken = result.tokens.refresh
        return result
    }

    func joinFamily(inviteCode: String, role: UserRole) async throws -> AuthResponse {
        let result: AuthResponse = try await post(
            path: "/auth/join-family/",
            body: ["invite_code": inviteCode, "role": role.rawValue]
        )
        authToken = result.tokens.access
        KeychainService.accessToken = result.tokens.access
        KeychainService.refreshToken = result.tokens.refresh
        return result
    }

    func logout() async throws {
        let _: EmptyResponse = try await post(path: "/auth/logout/")
        authToken = nil
        KeychainService.clearAll()
    }

    // MARK: - Profile
    func fetchProfile() async throws -> UserProfile { try await get(path: "/auth/me/") }
    func updateProfile(_ profile: UserProfile) async throws -> UserProfile { try await put(path: "/auth/me/", body: profile) }
    func fetchFamilyMembers() async throws -> [UserProfile] { try await get(path: "/families/members/") }
    func createFamily(name: String, elderName: String, elderBirthDate: String) async throws -> FamilyInfo {
        struct Req: Encodable { let name: String; let elderName: String; let elderBirthDate: String }
        return try await post(path: "/families/", body: Req(name: name, elderName: elderName, elderBirthDate: elderBirthDate))
    }

    // MARK: - Health
    func fetchHealthData(elderId: String) async throws -> HealthData { try await get(path: "/health-data/dashboard/") }
    func fetchWeeklySteps(elderId: String) async throws -> [Int] { try await get(path: "/health-data/weekly-steps/") }

    // MARK: - Chat
    func fetchChatRooms() async throws -> [ChatRoom] { try await get(path: "/chats/") }
    func fetchMessages(roomId: String) async throws -> [ChatMessage] { try await get(path: "/chats/\(roomId)/messages/") }
    func sendMessage(roomId: String, content: String) async throws -> ChatMessage {
        try await post(path: "/chats/\(roomId)/messages/", body: ["type": "text", "content": content])
    }
    func sendRequestMessage(roomId: String, messageType: String, referenceId: String, content: String) async throws -> ChatMessage {
        try await post(path: "/chats/\(roomId)/messages/", body: [
            "type": messageType, "reference_id": referenceId, "content": content
        ])
    }

    // MARK: - Care Log
    func fetchCareLogEntries(date: Date?) async throws -> [CareLogEntry] {
        if let date {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            let dateStr = formatter.string(from: date)
            return try await get(path: APIEndpoint.careLogs(on: dateStr))
        }
        return try await get(path: APIEndpoint.careLogs)
    }
    func createCareLogEntry(_ entry: CareLogEntry) async throws -> CareLogEntry { try await post(path: "/care-logs/", body: entry) }

    // MARK: - Medication
    func fetchMedications(elderId: String) async throws -> [Medication] { try await get(path: "/medications/") }
    func createMedication(_ medication: Medication) async throws -> Medication { try await post(path: "/medications/", body: medication) }
    func updateMedication(_ medication: Medication) async throws -> Medication { try await put(path: "/medications/\(medication.id)/", body: medication) }
    func fetchTodayConfirmations() async throws -> [MedicationConfirmation] { try await get(path: "/medications/today_confirmations/") }
    func confirmMedication(id: String, request: ConfirmMedicationRequest) async throws -> MedicationConfirmation {
        try await post(path: "/medications/\(id)/confirm/", body: request)
    }

    // MARK: - Expenses
    func fetchExpenses(month: Date?) async throws -> [Expense] { try await get(path: "/expenses/") }
    func fetchSpendingSummary(month: Date?) async throws -> SpendingSummary { try await get(path: "/expenses/monthly/") }
    func createExpense(_ expense: Expense) async throws -> Expense { try await post(path: "/expenses/", body: expense) }

    /// Request a presigned PUT URL from the backend, upload the JPEG bytes directly
    /// to object storage, then return the bare `image_url` to send back with the
    /// expense POST. Throws on encode/upload failure.
    func uploadReceiptImage(_ image: UIImage) async throws -> String {
        struct UploadURLResponse: Codable { let uploadUrl: String; let imageUrl: String }

        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw APIError.emptyResponse
        }

        let info: UploadURLResponse = try await post(
            path: "/expenses/upload-url/",
            body: ["content_type": "image/jpeg"]
        )

        guard let putURL = URL(string: info.uploadUrl) else { throw URLError(.badURL) }
        var putReq = URLRequest(url: putURL)
        putReq.httpMethod = "PUT"
        putReq.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.upload(for: putReq, from: data)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw APIError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return info.imageUrl
    }

    // MARK: - Todo
    func fetchTodos() async throws -> [TodoItem] { try await get(path: "/todos/") }
    func createTodo(_ todo: TodoItem) async throws -> TodoItem { try await post(path: "/todos/", body: todo) }
    func updateTodo(_ todo: TodoItem) async throws -> TodoItem { try await put(path: "/todos/\(todo.id)/", body: todo) }

    // MARK: - Calendar
    func fetchCalendarEvents(month: Date) async throws -> [CalendarEvent] { try await get(path: "/events/") }
    func createCalendarEvent(_ event: CalendarEvent) async throws -> CalendarEvent { try await post(path: "/events/", body: event) }
    func createCalendarEvents(_ events: [CalendarEvent]) async throws -> [CalendarEvent] { try await post(path: "/events/batch/", body: events) }

    // MARK: - Leave
    func fetchLeaveRequests() async throws -> [LeaveRequest] { try await get(path: "/leaves/") }
    func createLeaveRequest(_ request: LeaveRequest) async throws -> LeaveRequest { try await post(path: "/leaves/", body: request) }
    func updateLeaveStatus(id: String, status: LeaveStatus) async throws -> LeaveRequest {
        try await patch(path: "/leaves/\(id)/status/", body: ["status": status.rawValue])
    }
    func voteLeave(id: String, isAvailable: Bool) async throws -> LeaveRequest {
        try await post(path: "/leaves/\(id)/vote/", body: ["is_available": isAvailable])
    }

    // MARK: - Documents
    func fetchDocuments() async throws -> [AppDocument] { try await get(path: "/documents/") }
    /// Backend CreateDocumentSerializer requires `file_url, file_size, mime_type`.
    /// Caller must upload bytes to object storage first and supply the resulting URL.
    /// Until that flow exists, we send placeholders to avoid 400s on empty required fields.
    func uploadDocument(title: String, category: String, fileData: Data) async throws -> AppDocument {
        let body: [String: AnyEncodable] = [
            "title":     AnyEncodable(title),
            "category":  AnyEncodable(category),
            "file_url":  AnyEncodable(""),
            "file_size": AnyEncodable(fileData.count),
            "mime_type": AnyEncodable("application/octet-stream"),
        ]
        return try await post(path: "/documents/", body: body)
    }
    func deleteDocument(id: String) async throws { try await delete(path: APIEndpoint.document(id: id)) }

    // MARK: - Notifications
    func fetchNotifications() async throws -> [AppNotification] { try await get(path: "/notifications/") }
    func markNotificationRead(id: String) async throws {
        let _: EmptyResponse = try await put(path: "/notifications/\(id)/read/")
    }

    // MARK: - Purchase Requests
    func fetchPurchaseRequests() async throws -> [PurchaseRequest] { try await get(path: "/board/") }
    func createPurchaseRequest(_ request: PurchaseRequest) async throws -> PurchaseRequest { try await post(path: "/board/", body: request) }
    func updatePurchaseRequestStatus(id: String, status: String) async throws -> PurchaseRequest {
        try await patch(path: "/board/\(id)/status/", body: ["status": status])
    }

    // MARK: - AI
    func sendAIMessage(content: String) async throws -> AIMessage {
        try await post(path: "/ai/chat/", body: ["message": content])
    }

    // MARK: - Push Token
    func registerPushToken(_ token: String) async throws {
        let deviceName = UIDevice.current.name
        let _: EmptyResponse = try await post(path: "/notifications/device/", body: [
            "device_token": token,
            "platform":     "ios",
            "device_name":  deviceName,
        ])
    }

    // MARK: - First Aid
    func fetchFirstAidScenarios() async throws -> [FirstAidScenario] { try await get(path: "/ai/first-aid/") }

    // MARK: - SOS
    /// Backend TriggerSOSSerializer: `location` is a JSONField (dict), `situation` optional text.
    func triggerSOS(location: String?) async throws {
        var body: [String: AnyEncodable] = [:]
        if let location, !location.isEmpty {
            body["location"] = AnyEncodable(["address": location])
        }
        let _: EmptyResponse = try await post(path: "/sos/trigger/", body: body)
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
