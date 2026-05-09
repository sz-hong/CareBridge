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

    static let healthDashboard = "/health-data/dashboard/"
    static let healthWeeklySteps = "/health-data/weekly-steps/"

    static let chats = "/chats/"

    static let careLogs = "/care-logs/"

    static func careLogs(on date: String) -> String {
        "\(careLogs)?date=\(date)"
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

    static let notifications = "/notifications/"
    static let notificationDevice = "/notifications/device/"

    static func notificationRead(id: String) -> String {
        "/notifications/\(id)/read/"
    }

    static let board = "/board/"

    static func boardStatus(id: String) -> String {
        "/board/\(id)/status/"
    }

    static let aiChat = "/ai/chat/"
    static let aiFirstAid = "/ai/first-aid/"
    static let sosTrigger = "/sos/trigger/"

    static func chatMessages(roomId: String) -> String {
        "/chats/\(roomId)/messages/"
    }
}
