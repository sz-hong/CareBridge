import Foundation

extension APIDataService {
    // MARK: - Health
    func fetchHealthData(elderId: String) async throws -> HealthData { try await get(path: APIEndpoint.healthDashboard) }
    func fetchWeeklySteps(elderId: String) async throws -> [Int] { try await get(path: APIEndpoint.healthWeeklySteps) }
}
