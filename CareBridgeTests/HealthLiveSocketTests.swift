import Foundation
import Testing
@testable import CareBridge

private final class FakeHealthWebSocketTask: HealthWebSocketTasking {
    private(set) var didResume = false
    private(set) var didCancel = false
    private var receiveHandler: (@Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void)?
    private var pingHandler: (@Sendable (Error?) -> Void)?

    func resume() {
        didResume = true
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        didCancel = true
    }

    func receive(
        completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void
    ) {
        receiveHandler = completionHandler
    }

    func sendPing(pongReceiveHandler: @escaping @Sendable (Error?) -> Void) {
        pingHandler = pongReceiveHandler
    }

    func completeReceive(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        receiveHandler?(result)
    }

    func completePing(error: Error?) {
        pingHandler?(error)
    }
}

private final class ManualHealthSocketScheduler: HealthSocketScheduling {
    struct Scheduled {
        let delay: TimeInterval
        let work: @Sendable () -> Void
    }

    private(set) var scheduled: [Scheduled] = []

    func schedule(after delay: TimeInterval, _ work: @escaping @Sendable () -> Void) {
        scheduled.append(Scheduled(delay: delay, work: work))
    }

    func firstWork(after delay: TimeInterval) -> (@Sendable () -> Void)? {
        guard let index = scheduled.firstIndex(where: { $0.delay == delay }) else {
            return nil
        }
        return scheduled.remove(at: index).work
    }

    func hasScheduledWork(after delay: TimeInterval) -> Bool {
        scheduled.contains { $0.delay == delay }
    }
}

@MainActor
struct HealthLiveSocketTests {
    @Test func reconnectUsesLatestAccessTokenAfterReceiveFailure() async throws {
        let scheduler = ManualHealthSocketScheduler()
        var tokens = ["old-token", "new-token"]
        var createdURLs: [URL] = []
        var tasks: [FakeHealthWebSocketTask] = []
        let socket = HealthLiveSocket(
            tokenProvider: { tokens.removeFirst() },
            makeTask: { url in
                createdURLs.append(url)
                let task = FakeHealthWebSocketTask()
                tasks.append(task)
                return task
            },
            scheduler: scheduler,
            heartbeatInterval: 30
        )

        socket.connect()
        tasks[0].completeReceive(.failure(URLError(.networkConnectionLost)))
        await Task.yield()

        #expect(socket.isConnected == false)
        let reconnect = try #require(scheduler.firstWork(after: 1))
        reconnect()
        await Task.yield()

        #expect(createdURLs.map(\.absoluteString) == [
            "wss://api.carebridge-lab.com/ws/health/?token=old-token",
            "wss://api.carebridge-lab.com/ws/health/?token=new-token",
        ])
    }

    @Test func disconnectCancelsPendingReconnect() async throws {
        let scheduler = ManualHealthSocketScheduler()
        var createdCount = 0
        var tasks: [FakeHealthWebSocketTask] = []
        let socket = HealthLiveSocket(
            tokenProvider: { "token" },
            makeTask: { _ in
                createdCount += 1
                let task = FakeHealthWebSocketTask()
                tasks.append(task)
                return task
            },
            scheduler: scheduler,
            heartbeatInterval: 30
        )

        socket.connect()
        tasks[0].completeReceive(.failure(URLError(.networkConnectionLost)))
        await Task.yield()
        socket.disconnect()
        scheduler.firstWork(after: 1)?()
        await Task.yield()

        #expect(createdCount == 1)
        #expect(socket.isConnected == false)
    }

    @Test func heartbeatFailureMarksDisconnectedAndSchedulesReconnect() async throws {
        let scheduler = ManualHealthSocketScheduler()
        let task = FakeHealthWebSocketTask()
        let socket = HealthLiveSocket(
            tokenProvider: { "token" },
            makeTask: { _ in task },
            scheduler: scheduler,
            heartbeatInterval: 30
        )

        socket.connect()
        let heartbeat = try #require(scheduler.firstWork(after: 30))
        heartbeat()
        task.completePing(error: URLError(.timedOut))
        await Task.yield()

        #expect(socket.isConnected == false)
        #expect(scheduler.hasScheduledWork(after: 1))
    }
}