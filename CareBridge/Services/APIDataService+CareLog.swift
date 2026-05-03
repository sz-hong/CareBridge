import Foundation

extension APIDataService {
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
    func createCareLogEntry(_ entry: CareLogEntry) async throws -> CareLogEntry { try await post(path: APIEndpoint.careLogs, body: entry) }
}
