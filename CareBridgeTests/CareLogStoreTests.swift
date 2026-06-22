import Foundation
import Testing
@testable import CareBridge

private final class CareLogStoreService: MockDataService {
    var result: PaginatedResult<CareLogEntry>
    var fetchError: Error?

    init(entries: [CareLogEntry]) {
        result = PaginatedResult(
            items: entries,
            totalCount: entries.count,
            hasNextPage: false
        )
    }

    override func fetchCareLogEntries(
        date: Date?,
        type: CareLogType?,
        page: Int
    ) async throws -> PaginatedResult<CareLogEntry> {
        if let fetchError {
            throw fetchError
        }
        return result
    }
}

struct CareLogStoreTests {
    @Test
    func cancelledRefreshPreservesTimelineWithoutShowingError() async {
        let date = Date(timeIntervalSince1970: 1_750_665_600)
        let entry = CareLogEntry(
            id: "care-log-1",
            type: .activity,
            title: "散步",
            detail: "30 分鐘",
            timestamp: date,
            hasPhoto: false
        )
        let service = CareLogStoreService(entries: [entry])
        let store = CareLogStore(service: service)

        await store.loadTimeline(date: date, type: nil)
        service.fetchError = URLError(.cancelled)
        await store.loadTimeline(
            date: date,
            type: nil,
            forceRefresh: true
        )

        #expect(store.timelineEntries.map(\.id) == [entry.id])
        #expect(!store.isTimelineLoading)
        #expect(store.timelineErrorMessage == nil)
    }
}
