import Foundation
import UIKit

extension APIDataService {
    // MARK: - Notifications
    func fetchNotifications() async throws -> [AppNotification] { try await get(path: APIEndpoint.notifications) }
    func markNotificationRead(id: String) async throws {
        let _: EmptyResponse = try await put(path: APIEndpoint.notificationRead(id: id))
    }

    func registerPushToken(_ token: String) async throws {
        let deviceName = UIDevice.current.name
        let _: EmptyResponse = try await post(path: APIEndpoint.notificationDevice, body: [
            "device_token": token,
            "platform":     "ios",
            "device_name":  deviceName,
        ])
    }
}
