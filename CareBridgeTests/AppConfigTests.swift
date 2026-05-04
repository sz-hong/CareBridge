import Testing
@testable import CareBridge

struct AppConfigTests {
    @Test func publicTunnelIsDefaultBackendTarget() {
        #expect(AppConfig.mode == .publicTunnel)
        #expect(AppConfig.apiBaseURL == "https://api.carebridge-lab.com/api/v1")
        #expect(AppConfig.wsBaseURL == "wss://api.carebridge-lab.com/ws")
    }

    @Test func derivesSimulatorBackendURLs() {
        #expect(
            AppConfig.apiBaseURL(for: .simulator)
            == "http://127.0.0.1:8000/api/v1"
        )
        #expect(
            AppConfig.wsBaseURL(for: .simulator)
            == "ws://127.0.0.1:8000/ws"
        )
    }

    @Test func derivesDeviceBackendURLsFromLanAddress() {
        #expect(
            AppConfig.apiBaseURL(for: .device)
            == "http://100.125.106.32:8000/api/v1"
        )
        #expect(
            AppConfig.wsBaseURL(for: .device)
            == "ws://100.125.106.32:8000/ws"
        )
    }
}
