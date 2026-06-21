import Foundation

/// Centralized backend endpoint configuration.
///
/// Switch between simulator, physical device, and public tunnel by changing
/// `mode` below. All REST/WebSocket call sites derive their URLs from this
/// struct.
enum AppConfig {

    // Debug builds keep using the private test endpoint. App Store / Release
    // builds switch to the HTTPS Cloudflare Tunnel automatically.
#if DEBUG
    static let mode: Mode = .device
#else
    static let mode: Mode = .publicTunnel
#endif

    /// When targeting a physical device, update `lanIP` to your Mac's current
    /// LAN IP. Device and Mac must be on the same Wi-Fi.
    static let lanIP = "100.125.106.32"
    static let publicHost = "api.carebridge-lab.com"

    // MARK: - Derived
    enum Mode: Equatable {
        case simulator      // 127.0.0.1: iOS Simulator on this Mac
        case device         // LAN IP: physical iPhone/iPad on same Wi-Fi
        case publicTunnel   // Cloudflare Tunnel public HTTPS hostname
    }

    static let port = "8000"

    static var scheme: String { scheme(for: mode) }
    static var wsScheme: String { wsScheme(for: mode) }
    static var host: String { host(for: mode) }

    /// e.g. `https://api.carebridge-lab.com/api/v1`
    static var apiBaseURL: String { apiBaseURL(for: mode) }

    /// e.g. `wss://api.carebridge-lab.com/ws`
    static var wsBaseURL: String { wsBaseURL(for: mode) }

    static func apiBaseURL(for mode: Mode) -> String {
        "\(scheme(for: mode))://\(host(for: mode))/api/v1"
    }

    static func wsBaseURL(for mode: Mode) -> String {
        "\(wsScheme(for: mode))://\(host(for: mode))/ws"
    }

    static func host(for mode: Mode) -> String {
        switch mode {
        case .simulator: return "127.0.0.1:\(port)"
        case .device: return "\(lanIP):\(port)"
        case .publicTunnel: return publicHost
        }
    }

    static func scheme(for mode: Mode) -> String {
        mode == .publicTunnel ? "https" : "http"
    }

    static func wsScheme(for mode: Mode) -> String {
        mode == .publicTunnel ? "wss" : "ws"
    }
}
