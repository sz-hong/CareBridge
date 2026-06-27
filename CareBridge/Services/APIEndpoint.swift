import Foundation

enum APIEndpoint {
    static let authRegister = "/auth/register/"
    static let authLogin = "/auth/login/"
    static let authJoinFamily = "/auth/join-family/"
    static let authLogout = "/auth/logout/"
    static let authMe = "/auth/me/"
    static let tokenRefresh = "/auth/token/refresh/"

    static let families = "/families/"
    static let familyMembers = "/families/members/"
    static let familyHealthBinding = "/families/me/health-binding/"

    static let healthDashboard = "/health-data/dashboard/"
    static let healthWeeklySteps = "/health-data/weekly-steps/"
    static let healthSync = "/health-data/sync/"
    static let healthThresholds = "/health-data/thresholds/"
    static let healthAlerts = "/health-data/alerts/"

    /// 每日彙整的趨勢資料（家庭範圍，遠端家屬也適用）。
    static func healthHistory(type: String, dateFrom: String, dateTo: String) -> String {
        var components = URLComponents()
        components.path = "/health-data/"
        components.queryItems = [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "aggregation", value: "daily"),
            URLQueryItem(name: "date_from", value: dateFrom),
            URLQueryItem(name: "date_to", value: dateTo),
        ]
        return components.string ?? "/health-data/"
    }

    static let chats = "/chats/"

    static let careLogs = "/care-logs/"
    static let careLogUploadURL = "/care-logs/upload-url/"

    static func careLogs(on date: String) -> String {
        "\(careLogs)?date=\(date)"
    }

    static func careLogs(
        date: String?,
        type: CareLogType?,
        page: Int,
        pageSize: Int = 20
    ) -> String {
        var components = URLComponents()
        components.path = Self.careLogs
        components.queryItems = [
            date.map { URLQueryItem(name: "date", value: $0) },
            type.map { URLQueryItem(name: "type", value: $0.rawValue) },
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize)),
        ].compactMap { $0 }
        return components.string ?? Self.careLogs
    }

    static let medications = "/medications/"
    static let medicationTodayConfirmations = "/medications/today_confirmations/"

    static func medication(id: String) -> String {
        "/medications/\(id)/"
    }

    static func medicationConfirm(id: String) -> String {
        "/medications/\(id)/confirm/"
    }

    static let expenses = "/expenses/"
    static let expenseMonthly = "/expenses/monthly/"
    static let expenseUploadURL = "/expenses/upload-url/"

    static let todos = "/todos/"

    static func todo(id: String) -> String {
        "/todos/\(id)/"
    }

    static let events = "/events/"
    static let eventBatch = "/events/batch/"

    static let leaves = "/leaves/"

    static func leaveStatus(id: String) -> String {
        "/leaves/\(id)/status/"
    }

    static func leaveVote(id: String) -> String {
        "/leaves/\(id)/vote/"
    }

    static let documents = "/documents/"
    static let documentUploadURL = "/documents/upload-url/"

    static func document(id: String) -> String {
        "/documents/\(id)/"
    }

    static func documentApprove(id: String) -> String {
        "/documents/\(id)/approve/"
    }

    static let notifications = "/notifications/"
    static let notificationDevice = "/notifications/device/"
    static let notificationReadAll = "/notifications/read-all/"

    static func notificationRead(id: String) -> String {
        "/notifications/\(id)/read/"
    }

    static let board = "/board/"

    static func boardStatus(id: String) -> String {
        "/board/\(id)/status/"
    }

    static let aiChat = "/ai/chat/"
    static let aiTodaySummary = "/ai/today-summary/"
    static let aiFirstAid = "/ai/first-aid/"
    static let aiFirstAidScenarios = "/ai/first-aid/scenarios/"
    static let aiCareAnalysis = "/ai/care-analysis/"
    static let aiHandoverReport = "/ai/handover-report/"
    static let aiSubsidyForm = "/ai/subsidy-form/"
    static let sosTrigger = "/sos/trigger/"

    static func chatMessages(roomId: String) -> String {
        "/chats/\(roomId)/messages/"
    }
}
