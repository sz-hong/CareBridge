import Foundation

extension APIDataService {
    // MARK: - Calendar
    func fetchCalendarEvents(month: Date) async throws -> [CalendarEvent] { try await get(path: APIEndpoint.events) }
    func createCalendarEvent(_ event: CalendarEvent) async throws -> CalendarEvent { try await post(path: APIEndpoint.events, body: event) }
    func createCalendarEvents(_ events: [CalendarEvent]) async throws -> [CalendarEvent] { try await post(path: APIEndpoint.eventBatch, body: events) }
}
