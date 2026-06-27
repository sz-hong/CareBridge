import Foundation

@Observable
final class TodaySummaryStore {
    private let service: DataService
    private var hasLoadedForCurrentLogin = false

    var summary: TodaySummary?
    var isLoading = false
    var errorMessage: String?

    init(service: DataService = MockDataService()) {
        self.service = service
    }

    /// Clears the in-memory cache when a new login succeeds.
    @MainActor
    func invalidateForNewLogin() {
        hasLoadedForCurrentLogin = false
        summary = nil
        errorMessage = nil
        isLoading = false
    }

    /// Loads once per authenticated session. A successful login calls
    /// `invalidateForNewLogin()`, and this method fetches the summary the first
    /// time the logged-in UI appears.
    @MainActor
    func loadForCurrentLoginIfNeeded() async {
        guard !hasLoadedForCurrentLogin else { return }
        guard KeychainService.accessToken != nil else { return }
        guard !isLoading else { return }

        hasLoadedForCurrentLogin = true
        isLoading = true
        errorMessage = nil

        do {
            summary = try await service.fetchTodaySummary()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
