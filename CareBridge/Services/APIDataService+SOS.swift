import Foundation

extension APIDataService {
    // MARK: - SOS
    private struct SOSTriggerResult: Codable {
        let notifiedCount: Int
    }

    /// Triggers a backend SOS record. Backend `TriggerSOSSerializer`: `location`
    /// is a JSONField (dict), `situation` optional text. Returns the number of
    /// family members notified (in-app notification; no 119 dialing).
    func triggerSOS(location: String?) async throws -> Int {
        var body: [String: AnyEncodable] = [:]
        if let location, !location.isEmpty {
            body["location"] = AnyEncodable(["address": location])
        }
        let result: SOSTriggerResult = try await post(path: APIEndpoint.sosTrigger, body: body)
        return result.notifiedCount
    }
}
