import Foundation

/// WebSocket client for `/ws/health/`. Listens for live health updates pushed
/// by the backend whenever any family member's iPhone uploads new HealthKit
/// samples. Delivers `HealthLiveUpdate` payloads to `onUpdate` on the main
/// thread for the SwiftUI view to consume.
@Observable
final class HealthLiveSocket {
    private var task: URLSessionWebSocketTask?
    var isConnected = false
    var onUpdate: ((HealthLiveUpdate) -> Void)?

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func connect() {
        guard !isConnected else { return }
        var urlString = "\(AppConfig.wsBaseURL)/health/"
        if let token = KeychainService.accessToken {
            urlString += "?token=\(token)"
        }
        guard let url = URL(string: urlString) else { return }

        task = URLSession.shared.webSocketTask(with: url)
        task?.resume()
        isConnected = true
        receiveLoop()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        isConnected = false
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            switch result {
            case .success(.string(let text)):
                if let data = text.data(using: .utf8),
                   let update = try? self?.decoder.decode(HealthLiveUpdate.self, from: data) {
                    DispatchQueue.main.async { self?.onUpdate?(update) }
                }
                self?.receiveLoop()
            case .success(.data):
                self?.receiveLoop()
            case .failure:
                DispatchQueue.main.async { self?.isConnected = false }
            @unknown default:
                break
            }
        }
    }
}

/// Push payload from /ws/health/. Mirrors the backend `_broadcast_health_update`.
struct HealthLiveUpdate: Codable {
    var type: String      // "health.update"
    var points: [HealthLivePoint]
    var alerts: [HealthLiveAlert]
}

struct HealthLivePoint: Codable, Identifiable {
    var id: String
    var family: String
    var deviceId: String?
    var source: String?
    var type: String
    var value: Double
    var unit: String
    var recordedAt: Date
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, family, type, value, unit
        case deviceId   = "deviceId"   // already converted by .convertFromSnakeCase
        case source
        case recordedAt = "recordedAt"
        case createdAt  = "createdAt"
    }
}

struct HealthLiveAlert: Codable, Identifiable {
    var id: String
    var family: String
    var type: String
    var value: Double
    var threshold: Double
    var severity: String
    var recordedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, family, type, value, threshold, severity
        case recordedAt = "recordedAt"
    }
}
