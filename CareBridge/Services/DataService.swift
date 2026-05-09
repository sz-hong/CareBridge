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
    func fetchSpendingSummary(month: Date?) async throws -> SpendingSummary
    func createExpense(_ expense: Expense) async throws -> Expense
    /// Upload a locally redacted receipt image to quarantine storage.
    func uploadReceiptImage(_ image: UIImage) async throws -> ReceiptUploadReference

    // Todo
    func fetchTodos() async throws -> [TodoItem]
    func createTodo(_ todo: TodoItem) async throws -> TodoItem
    func updateTodo(_ todo: TodoItem) async throws -> TodoItem

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
    func streamAIResponse(prompt: String) -> AsyncThrowingStream<String, Error>

    // First Aid (static content, can be cached)
    func fetchFirstAidScenarios() async throws -> [FirstAidScenario]

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
