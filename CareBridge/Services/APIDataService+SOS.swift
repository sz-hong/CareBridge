import Foundation

extension APIDataService {
    // MARK: - SOS
    /// Backend TriggerSOSSerializer: `location` is a JSONField (dict), `situation` optional text.
    func triggerSOS(location: String?) async throws {
        var body: [String: AnyEncodable] = [:]
        if let location, !location.isEmpty {
            body["location"] = AnyEncodable(["address": location])
        }
        let _: EmptyResponse = try await post(path: APIEndpoint.sosTrigger, body: body)
    }
}
