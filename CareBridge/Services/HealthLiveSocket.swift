import Foundation

protocol HealthWebSocketTasking: AnyObject {
    func resume()
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func receive(
        completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void
    )
    func sendPing(pongReceiveHandler: @escaping @Sendable (Error?) -> Void)
}

final class URLSessionHealthWebSocketTask: HealthWebSocketTasking {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func resume() {
        task.resume()
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        task.cancel(with: closeCode, reason: reason)
    }

    func receive(
        completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void
    ) {
        task.receive { result in
            completionHandler(result)
        }
    }

    func sendPing(pongReceiveHandler: @escaping @Sendable (Error?) -> Void) {
        task.sendPing { error in
            pongReceiveHandler(error)
        }
    }
}

protocol HealthSocketScheduling: AnyObject {
    func schedule(after delay: TimeInterval, _ work: @escaping @Sendable () -> Void)
}

final class DispatchHealthSocketScheduler: HealthSocketScheduling {
    func schedule(after delay: TimeInterval, _ work: @escaping @Sendable () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            work()
        }
    }
}

/// WebSocket client for `/ws/health/`. It keeps the live health feed connected
/// across token refreshes, foreground resumes, and transient network drops.
@MainActor
@Observable
final class HealthLiveSocket {
    private var task: HealthWebSocketTasking?
    private var isClosing = false
    private var retryCount = 0

    var isConnected = false
    var onUpdate: ((HealthLiveUpdate) -> Void)?

    private let tokenProvider: @MainActor () -> String?
    private let makeTask: @MainActor (URL) -> HealthWebSocketTasking
    private let scheduler: HealthSocketScheduling
    private let heartbeatInterval: TimeInterval

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    init(
        tokenProvider: @escaping @MainActor () -> String? = { KeychainService.accessToken },
        makeTask: @escaping @MainActor (URL) -> HealthWebSocketTasking = { url in
            URLSessionHealthWebSocketTask(task: URLSession.shared.webSocketTask(with: url))
        },
        scheduler: HealthSocketScheduling = DispatchHealthSocketScheduler(),
        heartbeatInterval: TimeInterval = 30
    ) {
        self.tokenProvider = tokenProvider
        self.makeTask = makeTask
        self.scheduler = scheduler
        self.heartbeatInterval = heartbeatInterval
    }

    func connect() {
        isClosing = false
        guard !isConnected, task == nil else { return }
        openSocket()
    }

    func reconnectIfNeeded() {
        guard !isConnected else { return }
        connect()
    }

    func disconnect() {
        isClosing = true
        retryCount = 0
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    private func openSocket() {
        guard let url = makeURL() else { return }
        let nextTask = makeTask(url)
        task = nextTask
        isConnected = true
        nextTask.resume()
        receiveLoop(on: nextTask)
        scheduleHeartbeat(for: nextTask)
    }

    private func makeURL() -> URL? {
        guard let token = tokenProvider(), !token.isEmpty,
              var components = URLComponents(string: "\(AppConfig.wsBaseURL)/health/") else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    private func receiveLoop(on currentTask: HealthWebSocketTasking) {
        currentTask.receive { [weak self, weak currentTask] result in
            Task { @MainActor [weak self, weak currentTask] in
                guard let self,
                      let currentTask,
                      self.task === currentTask,
                      !self.isClosing else { return }

                switch result {
                case .success(.string(let text)):
                    self.retryCount = 0
                    if let data = text.data(using: .utf8),
                       let update = try? self.decoder.decode(HealthLiveUpdate.self, from: data) {
                        self.onUpdate?(update)
                    }
                    self.receiveLoop(on: currentTask)
                case .success(.data):
                    self.retryCount = 0
                    self.receiveLoop(on: currentTask)
                case .failure:
                    self.handleSocketFailure()
                @unknown default:
                    self.handleSocketFailure()
                }
            }
        }
    }

    private func scheduleHeartbeat(for currentTask: HealthWebSocketTasking) {
        scheduler.schedule(after: heartbeatInterval) { [weak self, weak currentTask] in
            Task { @MainActor [weak self, weak currentTask] in
                guard let self,
                      let currentTask,
                      self.task === currentTask,
                      self.isConnected,
                      !self.isClosing else { return }

                currentTask.sendPing { [weak self, weak currentTask] error in
                    Task { @MainActor [weak self, weak currentTask] in
                        guard let self,
                              let currentTask,
                              self.task === currentTask,
                              !self.isClosing else { return }
                        if error == nil {
                            self.retryCount = 0
                            self.scheduleHeartbeat(for: currentTask)
                        } else {
                            self.handleSocketFailure()
                        }
                    }
                }
            }
        }
    }

    private func handleSocketFailure() {
        guard !isClosing else { return }
        guard isConnected || task != nil else { return }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        let delay = min(pow(2.0, Double(retryCount)), 16.0)
        retryCount += 1
        scheduler.schedule(after: delay) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isClosing,
                      !self.isConnected,
                      self.task == nil else { return }
                self.openSocket()
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
        case deviceId   = "deviceId"
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
