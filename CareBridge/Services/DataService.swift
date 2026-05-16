import Foundation
import SwiftUI
import UIKit

// MARK: - Auth Response
struct AuthTokens: Codable {
    var access: String
    var refresh: String
}

struct AuthResponse: Codable {
    var user: UserProfile
    var tokens: AuthTokens
}

// MARK: - Generic API Response
struct APIResponse<T: Codable>: Codable {
    var success: Bool
    var data: T?
    var message: String?
}

// MARK: - Spending Summary
struct SpendingSummary: Codable {
    var monthlyTotal: Double
    var categoryBreakdown: [CategoryBreakdownItem]
}

struct ReceiptUploadReference: Codable {
    var uploadId: String
    var rawKey: String
}

struct CategoryBreakdownItem: Codable {
    var category: String
    var percentage: Double
}

// MARK: - HealthKit Sync Payloads

/// One sample being uploaded to /health-data/sync/. Type strings must match
/// the backend `HealthData.Type` enum (`heart_rate`, `blood_oxygen`, etc.).
struct HealthSyncItem: Codable {
    var type: String
    var value: Double
    var unit: String
    var recordedAt: Date
    var deviceId: String?
    /// Wire value for `HealthData.Source`: apple_watch / iphone / manual / other
    var source: String

    enum CodingKeys: String, CodingKey {
        case type, value, unit
        case recordedAt = "recorded_at"
        case deviceId   = "device_id"
        case source
    }
}

struct HealthSyncResult: Codable {
    var synced: Int
    var duplicates: Int
}

struct HealthAlertThresholdSettings: Codable, Equatable {
    var heartRateHigh: Int
    var heartRateLow: Int
    var bloodOxygenLow: Double

    init(heartRateHigh: Int, heartRateLow: Int, bloodOxygenLow: Double) {
        self.heartRateHigh = heartRateHigh
        self.heartRateLow = heartRateLow
        self.bloodOxygenLow = bloodOxygenLow
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        heartRateHigh = try c.decode(Int.self, forKey: .heartRateHigh)
        heartRateLow = try c.decode(Int.self, forKey: .heartRateLow)
        if let value = try? c.decode(Double.self, forKey: .bloodOxygenLow) {
            bloodOxygenLow = value
        } else {
            let value = try c.decode(String.self, forKey: .bloodOxygenLow)
            bloodOxygenLow = Double(value) ?? 93
        }
    }
}

/// 「目前是誰在同步這個家庭的健康資料」—— 對應後端
/// `/families/me/health-binding/` 的回應。`isOwner` 是以呼叫者為觀點判斷
/// 的，UI 用這個欄位決定 toggle 顯示打開 vs 顯示「目前由 X 同步」。
struct HealthBindingState: Codable, Equatable {
    // 後端用 snake_case 回來；APIClient 預設 keyDecodingStrategy =
    // .convertFromSnakeCase，所以這裡留 camelCase 即可。
    var isBound: Bool
    var isOwner: Bool
    var userId: String?
    var userName: String?
    var deviceId: String?
    var deviceLabel: String?
    var claimedAt: Date?
}

struct ClaimHealthBindingRequest: Codable {
    var deviceId: String
    var deviceLabel: String?
}

enum HealthBindingError: LocalizedError {
    case conflict
    case notOwner
    case noFamily
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .conflict:    return "此家庭已有另一支裝置在同步健康資料"
        case .notOwner:    return "只有目前綁定的裝置可以解除綁定"
        case .noFamily:    return "請先加入或建立家庭"
        case .unknown(let m): return m
        }
    }
}

enum AIResponseStreamEvent: Equatable {
    case chunk(String)
    case done(conversationID: String?)
    case ignore
}

// MARK: - DataService Protocol
protocol DataService {
    // Auth
    func register(name: String, email: String, password: String, phone: String?, language: String?) async throws -> AuthResponse
    func login(email: String, password: String) async throws -> AuthResponse
    func joinFamily(inviteCode: String, role: UserRole) async throws -> AuthResponse
    func logout() async throws

    // Profile
    func fetchProfile() async throws -> UserProfile
    func updateProfile(_ profile: UserProfile) async throws -> UserProfile
    func fetchFamilyMembers() async throws -> [UserProfile]
    func createFamily(name: String, elderName: String, elderBirthDate: String) async throws -> FamilyInfo

    // Health
    func fetchHealthData(elderId: String) async throws -> HealthData
    func fetchWeeklySteps(elderId: String) async throws -> [Int]
    /// Batch upload HealthKit samples to the backend. Idempotent —
    /// safe to retry; backend dedupes by (family, type, recorded_at).
    func syncHealthSamples(_ samples: [HealthSyncItem]) async throws -> HealthSyncResult

    // Health binding (one device per family for /health-data/sync/)
    func fetchHealthBinding() async throws -> HealthBindingState
    func claimHealthBinding(deviceId: String, deviceLabel: String?) async throws -> HealthBindingState
    func releaseHealthBinding() async throws -> HealthBindingState
    func fetchHealthThresholds() async throws -> HealthAlertThresholdSettings
    func updateHealthThresholds(_ thresholds: HealthAlertThresholdSettings) async throws -> HealthAlertThresholdSettings

    // Chat
    func fetchChatRooms() async throws -> [ChatRoom]
    func fetchMessages(roomId: String) async throws -> [ChatMessage]
    func sendMessage(roomId: String, content: String) async throws -> ChatMessage
    func sendRequestMessage(roomId: String, messageType: String, referenceId: String, content: String) async throws -> ChatMessage

    // Care Log
    func fetchCareLogEntries(date: Date?) async throws -> [CareLogEntry]
    func createCareLogEntry(_ entry: CareLogEntry) async throws -> CareLogEntry

    // Medication
    func fetchMedications(elderId: String) async throws -> [Medication]
    func createMedication(_ medication: Medication) async throws -> Medication
    func updateMedication(_ medication: Medication) async throws -> Medication
    func fetchTodayConfirmations() async throws -> [MedicationConfirmation]
    func confirmMedication(id: String, request: ConfirmMedicationRequest) async throws -> MedicationConfirmation

    // Expenses
    func fetchExpenses(month: Date?) async throws -> [Expense]
    func fetchExpense(id: String) async throws -> Expense
    func fetchSpendingSummary(month: Date?) async throws -> SpendingSummary
    func createExpense(_ expense: Expense) async throws -> Expense
    /// Upload a locally redacted receipt image to quarantine storage.
    func uploadReceiptImage(_ image: UIImage) async throws -> ReceiptUploadReference

    // Todo
    func fetchTodos() async throws -> [TodoItem]
    func createTodo(_ todo: TodoItem) async throws -> TodoItem
    func updateTodo(_ todo: TodoItem) async throws -> TodoItem
    func deleteTodo(id: String) async throws

    // Calendar
    func fetchCalendarEvents(month: Date) async throws -> [CalendarEvent]
    func createCalendarEvent(_ event: CalendarEvent) async throws -> CalendarEvent
    func createCalendarEvents(_ events: [CalendarEvent]) async throws -> [CalendarEvent]

    // Leave
    func fetchLeaveRequests() async throws -> [LeaveRequest]
    func createLeaveRequest(_ request: LeaveRequest) async throws -> LeaveRequest
    func updateLeaveStatus(id: String, status: LeaveStatus) async throws -> LeaveRequest
    func voteLeave(id: String, isAvailable: Bool) async throws -> LeaveRequest

    // Documents
    func fetchDocuments() async throws -> [AppDocument]
    func uploadDocument(title: String, category: String, fileData: Data) async throws -> AppDocument
    func deleteDocument(id: String) async throws

    // Notifications
    func fetchNotifications() async throws -> [AppNotification]
    func markNotificationRead(id: String) async throws

    // Purchase Requests
    func fetchPurchaseRequests() async throws -> [PurchaseRequest]
    func createPurchaseRequest(_ request: PurchaseRequest) async throws -> PurchaseRequest
    func updatePurchaseRequestStatus(id: String, status: String) async throws -> PurchaseRequest

    // AI
    func sendAIMessage(content: String) async throws -> AIMessage
    func fetchCareAnalysis(days: Int) async throws -> AICareAnalysisResponse
    func generateHandoverReport(date: String) async throws -> AIHandoverReportResponse
    func generateSubsidyForm(formType: String) async throws -> AISubsidyFormResponse
    func streamAIResponse(
        prompt: String,
        conversationID: String?
    ) -> AsyncThrowingStream<AIResponseStreamEvent, Error>

    // First Aid (static content, can be cached)
    func fetchFirstAidScenarios() async throws -> [FirstAidScenario]
    func askFirstAid(query: String) async throws -> FirstAidAnswer

    // SOS
    func triggerSOS(location: String?) async throws

    // Push Notifications
    func registerPushToken(_ token: String) async throws
}

// MARK: - Environment Key

private struct DataServiceKey: EnvironmentKey {
    static let defaultValue: DataService = MockDataService()
}

extension EnvironmentValues {
    var dataService: DataService {
        get { self[DataServiceKey.self] }
        set { self[DataServiceKey.self] = newValue }
    }
}
