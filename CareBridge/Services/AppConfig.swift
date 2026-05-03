import Foundation

/// Centralized backend endpoint configuration.
///
/// Switch between simulator and physical device by changing `mode` below.
/// All REST/WebSocket call sites derive their URLs from this struct.
enum AppConfig {

    // MARK: - 🔧 Switch here
    /// Change this one line to flip between targets.
    //static let mode: Mode = .simulator
    static let mode: Mode = .device

    /// When targeting a physical device, update `lanIP` to your Mac's current
    /// LAN IP (check with `ipconfig getifaddr en0`). Device and Mac must be
    /// on the same Wi-Fi.

    //static let lanIP = "192.168.1.110"
    static let lanIP = "100.125.106.32"

    // MARK: - Derived
    enum Mode {
        case simulator      // 127.0.0.1 — iOS Simulator on this Mac
        case device         // LAN IP    — physical iPhone/iPad on same Wi-Fi
    }

    static let port = "8000"
    static let scheme = "http"
    static let wsScheme = "ws"

    static var host: String {
        switch mode {
        case .simulator: return "127.0.0.1:\(port)"
        case .device:    return "\(lanIP):\(port)"
        }
    }

    /// e.g. `http://127.0.0.1:8000/api/v1`
    static var apiBaseURL: String { "\(scheme)://\(host)/api/v1" }

    /// e.g. `ws://127.0.0.1:8000/ws`
    static var wsBaseURL: String { "\(wsScheme)://\(host)/ws" }
}
