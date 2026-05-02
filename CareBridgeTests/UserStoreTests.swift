import Foundation
import Testing
@testable import CareBridge

private enum UserStoreTestError: LocalizedError {
    case failed

    var errorDescription: String? { "Profile unavailable" }
}

private final class UserStoreService: MockDataService {
    var shouldFail = false

    override func fetchProfile() async throws -> UserProfile {
        if shouldFail { throw UserStoreTestError.failed }
        return UserProfile(
            id: "profile-1",
            name: "Profile",
            email: "profile@example.com",
            role: .family,
            family: FamilyInfo(id: "family-1", name: "Family")
        )
    }

    override func fetchFamilyMembers() async throws -> [UserProfile] {
        if shouldFail { throw UserStoreTestError.failed }
        return [
            UserProfile(
                id: "member-1",
                name: "Member",
                email: "member@example.com",
                role: .caregiver,
                family: FamilyInfo(id: "family-1", name: "Family")
            )
        ]
    }
}

struct UserStoreTests {
    @Test func reloadPopulatesProfileAndMembers() async {
        let service = UserStoreService()
        let store = UserStore(service: service)

        await store.reload()

        #expect(store.currentUser?.id == "profile-1")
        #expect(store.familyMembers.map(\.id) == ["member-1"])
        #expect(!store.isLoading)
        #expect(store.errorMessage == nil)
    }

    @Test func reloadFailurePreservesExistingProfileAndExposesError() async {
        let service = UserStoreService()
        let store = UserStore(service: service)
        store.populate(from: AuthResponse(
            user: UserProfile(id: "cached", name: "Cached", email: "cached@example.com"),
            tokens: AuthTokens(access: "access", refresh: "refresh")
        ))
        service.shouldFail = true

        await store.reload()

        #expect(store.currentUser?.id == "cached")
        #expect(store.familyMembers.isEmpty)
        #expect(!store.isLoading)
        #expect(store.errorMessage == "Profile unavailable")
    }
}
