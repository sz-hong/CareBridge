import Foundation
import UIKit

/// Mock implementation returning sample data for development & preview.
class MockDataService: DataService {

    // MARK: - Auth
    func register(name: String, email: String, password: String, phone: String?, language: String?) async throws -> AuthResponse {
        AuthResponse(
            user: UserProfile(id: UUID().uuidString, name: name, email: email,
                              phone: phone, role: nil, family: nil),
            tokens: AuthTokens(access: "mock-access-\(UUID().uuidString)", refresh: "mock-refresh")
        )
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        AuthResponse(
            user: UserProfile(id: "u1", name: "Hank Chen", email: email,
                              phone: "+886 912-345-678", birthday: "1990/05/15",
                              role: .family, family: FamilyInfo(id: "f1", name: "Chen Family")),
            tokens: AuthTokens(access: "mock-access-\(UUID().uuidString)", refresh: "mock-refresh")
        )
    }

    func joinFamily(inviteCode: String, role: UserRole) async throws -> AuthResponse {
        try await login(email: "hank@carebridge.com", password: "")
    }

    func logout() async throws { }

    // MARK: - Profile
    func fetchProfile() async throws -> UserProfile {
        UserProfile(id: "u1", name: "Hank Chen", email: "hank@carebridge.com",
                    phone: "+886 912-345-678", birthday: "1990/05/15",
                    role: .family, family: FamilyInfo(id: "f1", name: "Chen Family"))
    }

    func updateProfile(_ profile: UserProfile) async throws -> UserProfile { profile }

    func createFamily(name: String, elderName: String, elderBirthDate: String) async throws -> FamilyInfo {
        FamilyInfo(id: UUID().uuidString, name: name)
    }

    func fetchFamilyMembers() async throws -> [UserProfile] {
        [
            UserProfile(id: "u2", name: "Rita Santos", email: "rita@carebridge.com",
                        role: .caregiver, family: FamilyInfo(id: "f1", name: "Chen Family")),
            UserProfile(id: "u3", name: "林小明", email: "ming@carebridge.com",
                        role: .family, family: FamilyInfo(id: "f1", name: "Chen Family")),
        ]
    }

    // MARK: - Health
    func fetchHealthData(elderId: String) async throws -> HealthData { .sample }
    func fetchWeeklySteps(elderId: String) async throws -> [Int] { HealthData.weeklySteps }
    func fetchHealthHistory(type: String, days: Int) async throws -> [HealthHistoryPoint] { [] }
    func fetchHealthAlerts() async throws -> [HealthAlert] { [] }
    func syncHealthSamples(_ samples: [HealthSyncItem]) async throws -> HealthSyncResult {
        HealthSyncResult(synced: samples.count, duplicates: 0)
    }
    func fetchHealthBinding() async throws -> HealthBindingState {
        HealthBindingState(isBound: false, isOwner: false, userId: nil, userName: nil,
                           deviceId: nil, deviceLabel: nil, claimedAt: nil)
    }
    func claimHealthBinding(deviceId: String, deviceLabel: String?) async throws -> HealthBindingState {
        HealthBindingState(isBound: true, isOwner: true, userId: "mock", userName: "Mock",
                           deviceId: deviceId, deviceLabel: deviceLabel, claimedAt: Date())
    }
    func releaseHealthBinding() async throws -> HealthBindingState {
        HealthBindingState(isBound: false, isOwner: false, userId: nil, userName: nil,
                           deviceId: nil, deviceLabel: nil, claimedAt: nil)
    }
    func fetchHealthThresholds() async throws -> HealthAlertThresholdSettings {
        HealthAlertThresholdSettings(heartRateHigh: 100, heartRateLow: 50, bloodOxygenLow: 93)
    }
    func updateHealthThresholds(_ thresholds: HealthAlertThresholdSettings) async throws -> HealthAlertThresholdSettings {
        thresholds
    }

    // MARK: - Chat
    func fetchChatRooms() async throws -> [ChatRoom] { ChatRoom.samples }
    func fetchMessages(roomId: String) async throws -> [ChatMessage] { ChatMessage.samples }
    func sendMessage(roomId: String, content: String) async throws -> ChatMessage {
        ChatMessage(id: UUID().uuidString, sender: "我", senderRole: .family,
                    content: content, translations: nil, timestamp: Date(), isMe: true)
    }
    func sendRequestMessage(roomId: String, messageType: String, referenceId: String, content: String) async throws -> ChatMessage {
        ChatMessage(id: UUID().uuidString, sender: "我", senderRole: .family,
                    content: content, translations: nil, timestamp: Date(), isMe: true,
                    messageType: messageType, referenceId: referenceId)
    }

    // MARK: - Care Log
    func fetchCareLogEntries(
        date: Date?,
        type: CareLogType?,
        page: Int
    ) async throws -> PaginatedResult<CareLogEntry> {
        let calendar = Calendar.current
        let filtered = CareLogEntry.samples.filter { entry in
            let matchesDate = date.map {
                calendar.isDate(entry.timestamp, inSameDayAs: $0)
            } ?? true
            let matchesType = type.map { entry.type == $0 } ?? true
            return matchesDate && matchesType
        }
        let pageSize = 20
        let start = max(page - 1, 0) * pageSize
        let items = start < filtered.count
            ? Array(filtered.dropFirst(start).prefix(pageSize))
            : []
        return PaginatedResult(
            items: items,
            totalCount: filtered.count,
            hasNextPage: start + items.count < filtered.count
        )
    }
    func uploadCareLogPhoto(_ image: UIImage) async throws -> CareLogPhotoUploadReference {
        CareLogPhotoUploadReference(
            photoKey: "care-logs/mock-family/photos/mock-photo.jpg"
        )
    }
    func createCareLogEntry(_ entry: CareLogEntry) async throws -> CareLogEntry { entry }
    func deleteCareLogEntry(id: String) async throws { }

    // MARK: - Medication
    func fetchMedications(elderId: String) async throws -> [Medication] { Medication.samples }
    func createMedication(_ medication: Medication) async throws -> Medication { medication }
    func updateMedication(_ medication: Medication) async throws -> Medication { medication }
    func deleteMedication(id: String) async throws { }
    func fetchTodayConfirmations() async throws -> [MedicationConfirmation] { [] }
    func confirmMedication(id: String, request: ConfirmMedicationRequest) async throws -> MedicationConfirmation {
        MedicationConfirmation(id: UUID().uuidString, medication: id, scheduledTime: request.scheduledTime, confirmedAt: Date(), photoUrl: request.photoUrl, note: request.note)
    }

    // MARK: - Expenses
    func fetchExpenses(month: Date?) async throws -> [Expense] { Expense.samples }
    func fetchExpense(id: String) async throws -> Expense {
        Expense.samples.first(where: { $0.id == id }) ?? Expense.samples[0]
    }
    func fetchSpendingSummary(month: Date?) async throws -> SpendingSummary {
        SpendingSummary(monthlyTotal: 24850, categoryBreakdown: [
            CategoryBreakdownItem(category: "醫療保健", percentage: 45),
            CategoryBreakdownItem(category: "日常飲食", percentage: 25),
            CategoryBreakdownItem(category: "生活用品", percentage: 20),
            CategoryBreakdownItem(category: "其他支出", percentage: 10),
        ])
    }
    func createExpense(_ expense: Expense) async throws -> Expense { expense }
    func updateExpense(_ expense: Expense) async throws -> Expense { expense }
    func deleteExpense(id: String) async throws { }
    func uploadReceiptImage(_ image: UIImage) async throws -> ReceiptUploadReference {
        ReceiptUploadReference(uploadId: UUID().uuidString, rawKey: "quarantine/mock/receipts/mock.jpg")
    }

    // MARK: - Todo
    func fetchTodos() async throws -> [TodoItem] { TodoItem.samples }
    func createTodo(_ todo: TodoItem) async throws -> TodoItem { todo }
    func updateTodo(_ todo: TodoItem) async throws -> TodoItem { todo }
    func deleteTodo(id: String) async throws { }

    // MARK: - Calendar
    func fetchCalendarEvents(month: Date) async throws -> [CalendarEvent] { CalendarEvent.samples }
    func createCalendarEvent(_ event: CalendarEvent) async throws -> CalendarEvent { event }
    func createCalendarEvents(_ events: [CalendarEvent]) async throws -> [CalendarEvent] { events }

    // MARK: - Leave
    func fetchLeaveRequests() async throws -> [LeaveRequest] { LeaveRequest.samples }
    func createLeaveRequest(_ request: LeaveRequest) async throws -> LeaveRequest { request }
    func updateLeaveStatus(id: String, status: LeaveStatus) async throws -> LeaveRequest {
        var req = LeaveRequest.samples[0]
        req.status = status
        return req
    }
    func voteLeave(id: String, isAvailable: Bool) async throws -> LeaveRequest {
        var req = LeaveRequest.samples[0]
        req.votes = [LeaveVote(id: UUID().uuidString, memberId: "mock", memberName: "林小明", isAvailable: isAvailable, votedAt: Date())]
        return req
    }

    // MARK: - Documents
    func fetchDocuments() async throws -> [AppDocument] { AppDocument.samples }
    func uploadDocument(title: String, category: String, fileData: Data) async throws -> AppDocument {
        AppDocument(id: UUID().uuidString, title: title, category: category,
                    fileSize: "\(fileData.count / 1024) KB", uploadDate: Date())
    }
    func deleteDocument(id: String) async throws { }
    func approveDocument(id: String) async throws -> AppDocument {
        let existing = AppDocument.samples.first { $0.id == id }
        return AppDocument(
            id: id,
            title: existing?.title ?? "Document",
            category: existing?.category ?? "other",
            fileSize: existing?.fileSize ?? "0 KB",
            uploadDate: existing?.uploadDate ?? Date(),
            remoteURL: existing?.remoteURL,
            deidStatus: "completed"
        )
    }

    // MARK: - Notifications
    func fetchNotifications() async throws -> [AppNotification] { AppNotification.samples }
    func markNotificationRead(id: String) async throws { }
    func markAllNotificationsRead() async throws { }

    // MARK: - Purchase Requests
    func fetchPurchaseRequests() async throws -> [PurchaseRequest] { PurchaseRequest.samples }
    func createPurchaseRequest(_ request: PurchaseRequest) async throws -> PurchaseRequest { request }
    func updatePurchaseRequestStatus(id: String, status: String) async throws -> PurchaseRequest {
        var req = PurchaseRequest.samples[0]
        req.status = status
        return req
    }

    // MARK: - AI
    func sendAIMessage(content: String) async throws -> AIMessage {
        AIMessage(id: UUID().uuidString,
                  content: "這是 AI 的模擬回覆。正式版本將連接後端 AI 服務。",
                  isUser: false, timestamp: Date())
    }

    func fetchTodaySummary() async throws -> TodaySummary {
        TodaySummary(
            summary: "今日有 2 筆照護紀錄、1 個待辦與 3 項用藥，請留意晚間用藥。",
            date: "2026-06-27",
            sourceCounts: TodaySummary.SourceCounts(
                careLogs: 2,
                todos: 1,
                medications: 3
            ),
            tokensUsed: 123
        )
    }

    func fetchCareAnalysis(days: Int) async throws -> AICareAnalysisResponse {
        AICareAnalysisResponse(
            analysis: "Mock care analysis for the last \(days) days.",
            periodDays: days,
            tokensUsed: 0
        )
    }

    func generateHandoverReport(date: String) async throws -> AIHandoverReportResponse {
        AIHandoverReportResponse(
            report: "Mock handover report for \(date).",
            date: date,
            tokensUsed: 0
        )
    }

    func generateSubsidyForm(
        formType: String,
        templateFileName: String?,
        templateFileData: Data?
    ) async throws -> AISubsidyFormResponse {
        AISubsidyFormResponse(
            formType: formType,
            templateName: templateFileName ?? "Mock subsidy form",
            formFields: [
                "applicant": "Mock elder",
                "care_need": "Daily assistance"
            ],
            tokensUsed: 0
        )
    }

    func streamAIResponse(
        prompt: String,
        conversationID: String?
    ) -> AsyncThrowingStream<AIResponseStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let chunks = [
                    "這是 AI 的模擬串流回覆：",
                    prompt,
                    "。正式版本會連接後端 SSE。",
                ]
                for chunk in chunks {
                    continuation.yield(.chunk(chunk))
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
                continuation.yield(
                    .done(conversationID: conversationID ?? "mock-ai-conversation")
                )
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - First Aid
    func fetchFirstAidScenarios() async throws -> [FirstAidScenario] { FirstAidScenario.samples }

    func askFirstAid(query: String) async throws -> FirstAidAnswer {
        FirstAidAnswer(
            answer: "Mock first-aid answer for: \(query)",
            sources: [],
            tokensUsed: 0
        )
    }

    // MARK: - SOS
    func triggerSOS(location: String?) async throws -> Int { 3 }

    // MARK: - Push Notifications
    func registerPushToken(_ token: String) async throws { }
}
