import Foundation

/// Mock implementation returning sample data for development & preview.
class MockDataService: DataService {

    // MARK: - Auth
    func login(email: String, password: String) async throws -> AuthResponse {
        AuthResponse(
            user: UserProfile(id: "u1", name: "Hank Chen", email: email,
                              phone: "+886 912-345-678", birthday: "1990/05/15",
                              role: .family, family: FamilyInfo(id: "f1", name: "Chen Family")),
            tokens: AuthTokens(access: "mock-access-\(UUID().uuidString)", refresh: "mock-refresh")
        )
    }

    func joinFamily(inviteCode: String) async throws -> AuthResponse {
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

    // MARK: - Chat
    func fetchChatRooms() async throws -> [ChatRoom] { ChatRoom.samples }
    func fetchMessages(roomId: String) async throws -> [ChatMessage] { ChatMessage.samples }
    func sendMessage(roomId: String, content: String) async throws -> ChatMessage {
        ChatMessage(id: UUID().uuidString, sender: "我", senderRole: .family,
                    content: content, translatedContent: nil, timestamp: Date(), isMe: true)
    }

    // MARK: - Care Log
    func fetchCareLogEntries(date: Date?) async throws -> [CareLogEntry] { CareLogEntry.samples }
    func createCareLogEntry(_ entry: CareLogEntry) async throws -> CareLogEntry { entry }

    // MARK: - Medication
    func fetchMedications(elderId: String) async throws -> [Medication] { Medication.samples }
    func createMedication(_ medication: Medication) async throws -> Medication { medication }
    func updateMedication(_ medication: Medication) async throws -> Medication { medication }
    func fetchTodayConfirmations() async throws -> [MedicationConfirmation] { [] }
    func confirmMedication(id: String, request: ConfirmMedicationRequest) async throws -> MedicationConfirmation {
        MedicationConfirmation(id: UUID().uuidString, medication: id, scheduledTime: request.scheduledTime, confirmedAt: Date(), photoUrl: request.photoUrl, note: request.note)
    }

    // MARK: - Expenses
    func fetchExpenses(month: Date?) async throws -> [Expense] { Expense.samples }
    func fetchSpendingSummary(month: Date?) async throws -> SpendingSummary {
        SpendingSummary(monthlyTotal: 24850, categoryBreakdown: [
            CategoryBreakdownItem(category: "醫療保健", percentage: 45),
            CategoryBreakdownItem(category: "日常飲食", percentage: 25),
            CategoryBreakdownItem(category: "生活用品", percentage: 20),
            CategoryBreakdownItem(category: "其他支出", percentage: 10),
        ])
    }
    func createExpense(_ expense: Expense) async throws -> Expense { expense }

    // MARK: - Todo
    func fetchTodos() async throws -> [TodoItem] { TodoItem.samples }
    func createTodo(_ todo: TodoItem) async throws -> TodoItem { todo }
    func updateTodo(_ todo: TodoItem) async throws -> TodoItem { todo }

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

    // MARK: - Documents
    func fetchDocuments() async throws -> [AppDocument] { AppDocument.samples }
    func uploadDocument(title: String, category: String, fileData: Data) async throws -> AppDocument {
        AppDocument(id: UUID().uuidString, title: title, category: category,
                    fileSize: "\(fileData.count / 1024) KB", uploadDate: Date())
    }
    func deleteDocument(id: String) async throws { }

    // MARK: - Notifications
    func fetchNotifications() async throws -> [AppNotification] { AppNotification.samples }
    func markNotificationRead(id: String) async throws { }

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

    // MARK: - First Aid
    func fetchFirstAidScenarios() async throws -> [FirstAidScenario] { FirstAidScenario.samples }

    // MARK: - SOS
    func triggerSOS(location: String?) async throws { }

    // MARK: - Push Notifications
    func registerPushToken(_ token: String) async throws { }
}
