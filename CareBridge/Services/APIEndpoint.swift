import Foundation

enum APIEndpoint {
    static let tokenRefresh = "/auth/token/refresh/"
    static let careLogs = "/care-logs/"

    static func careLogs(on date: String) -> String {
        "\(careLogs)?date=\(date)"
    }

    static func document(id: String) -> String {
        "/documents/\(id)/"
    }
}
