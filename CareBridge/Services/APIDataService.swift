import Foundation
import UIKit

/// Real API implementation — connects to backend REST API via JSON.
/// Replace `baseURL` with your actual server address.
class APIDataService: DataService {

    private let baseURL: String
    private var authToken: String?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: String = "http://127.0.0.1:8000/api/v1") {
        self.baseURL = baseURL
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.authToken = KeychainService.accessToken
    }

    // MARK: - Generic Request Helpers

    private func request<T: Codable>(_ method: String, path: String, body: (any Encodable)? = nil) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            let http = response as? HTTPURLResponse
            throw APIError.serverError(statusCode: http?.statusCode ?? 0)
        }

        let apiResponse = try decoder.decode(APIResponse<T>.self, from: data)
        guard let result = apiResponse.data else {
            throw APIError.emptyResponse
        }
        return result
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

    func joinFamily(inviteCode: String) async throws -> AuthResponse {
        let result: AuthResponse = try await post(path: "/auth/join-family/", body: ["invite_code": inviteCode])
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

    // MARK: - Health
    func fetchHealthData(elderId: String) async throws -> HealthData { try await get(path: "/health-data/dashboard/") }
    func fetchWeeklySteps(elderId: String) async throws -> [Int] { try await get(path: "/health-data/weekly-steps/") }

    // MARK: - Chat
    func fetchChatRooms() async throws -> [ChatRoom] { try await get(path: "/chats/") }
    func fetchMessages(roomId: String) async throws -> [ChatMessage] { try await get(path: "/chats/\(roomId)/messages/") }
    func sendMessage(roomId: String, content: String) async throws -> ChatMessage {
        try await post(path: "/chats/\(roomId)/messages/", body: ["type": "text", "content": content])
    }

    // MARK: - Care Log
    func fetchCareLogEntries(date: Date?) async throws -> [CareLogEntry] {
        if let date {
            let dateStr = ISO8601DateFormatter().string(from: date)
            return try await get(path: "/care-logs/?date=\(dateStr)")
        }
        return try await get(path: "/care-logs/")
    }
    func createCareLogEntry(_ entry: CareLogEntry) async throws -> CareLogEntry { try await post(path: "/care-logs/", body: entry) }

    // MARK: - Medication
    func fetchMedications(elderId: String) async throws -> [Medication] { try await get(path: "/medications/") }
    func createMedication(_ medication: Medication) async throws -> Medication { try await post(path: "/medications/", body: medication) }
    func updateMedication(_ medication: Medication) async throws -> Medication { try await put(path: "/medications/\(medication.id)", body: medication) }
    func fetchTodayConfirmations() async throws -> [MedicationConfirmation] { try await get(path: "/medications/today_confirmations") }
    func confirmMedication(id: String, request: ConfirmMedicationRequest) async throws -> MedicationConfirmation {
        try await post(path: "/medications/\(id)/confirm", body: request)
    }

    // MARK: - Expenses
    func fetchExpenses(month: Date?) async throws -> [Expense] { try await get(path: "/expenses/") }
    func fetchSpendingSummary(month: Date?) async throws -> SpendingSummary { try await get(path: "/expenses/monthly/") }
    func createExpense(_ expense: Expense) async throws -> Expense { try await post(path: "/expenses/", body: expense) }

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
    func deleteDocument(id: String) async throws { try await delete(path: "/documents/\(id)/") }

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
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .serverError(let code): return "伺服器錯誤 (\(code))"
        case .emptyResponse: return "伺服器回傳空資料"
        }
    }
}

struct EmptyResponse: Codable {}

struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        _encode = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
