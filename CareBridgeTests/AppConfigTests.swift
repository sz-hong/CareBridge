import Testing
@testable import CareBridge

struct AppConfigTests {
    @Test func everyBuildUsesPublicAPI() {
        #expect(AppConfig.apiBaseURL == "https://api.carebridge-lab.com/api/v1")
        #expect(AppConfig.wsBaseURL == "wss://api.carebridge-lab.com/ws")
    }
}
