import Foundation

extension APIDataService {
    // MARK: - Profile
    func fetchProfile() async throws -> UserProfile { try await get(path: APIEndpoint.authMe) }
    func updateProfile(_ profile: UserProfile) async throws -> UserProfile { try await put(path: APIEndpoint.authMe, body: profile) }
    func fetchFamilyMembers() async throws -> [UserProfile] { try await get(path: APIEndpoint.familyMembers) }
    func createFamily(name: String, elderName: String, elderBirthDate: String) async throws -> FamilyInfo {
        struct Req: Encodable { let name: String; let elderName: String; let elderBirthDate: String }
        return try await post(path: APIEndpoint.families, body: Req(name: name, elderName: elderName, elderBirthDate: elderBirthDate))
    }
}
