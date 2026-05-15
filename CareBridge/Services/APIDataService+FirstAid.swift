import Foundation

extension APIDataService {
    // MARK: - First Aid
    func fetchFirstAidScenarios() async throws -> [FirstAidScenario] {
        try await get(path: APIEndpoint.aiFirstAidScenarios)
    }

    func askFirstAid(query: String) async throws -> FirstAidAnswer {
        try await post(
            path: APIEndpoint.aiFirstAid,
            body: FirstAidQueryRequestBody(query: query)
        )
    }
}
