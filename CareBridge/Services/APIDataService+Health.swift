import Foundation

extension APIDataService {
    // MARK: - Health
    func fetchHealthData(elderId: String) async throws -> HealthData { try await get(path: APIEndpoint.healthDashboard) }
    func fetchWeeklySteps(elderId: String) async throws -> [Int] { try await get(path: APIEndpoint.healthWeeklySteps) }

    func syncHealthSamples(_ samples: [HealthSyncItem]) async throws -> HealthSyncResult {
        // Backend expects {"data": [...]}; response envelope is unwrapped by APIClient.
        struct Body: Encodable { let data: [HealthSyncItem] }
        return try await post(path: APIEndpoint.healthSync, body: Body(data: samples))
    }
}
