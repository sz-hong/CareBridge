import Foundation

extension APIDataService {
    // MARK: - First Aid
    func fetchFirstAidScenarios() async throws -> [FirstAidScenario] { try await get(path: APIEndpoint.aiFirstAid) }
}
