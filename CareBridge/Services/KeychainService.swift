import Foundation
import Security

/// JWT 令牌的 Keychain 存取封裝。
/// 使用 kSecClassGenericPassword 安全存儲 access/refresh token。
enum KeychainService {
    private static let service = Bundle.main.bundleIdentifier ?? "com.carebridge.app"
    private static let accessKey  = "jwt_access_token"
    private static let refreshKey = "jwt_refresh_token"
    private static let deviceTokenKey = "apns_device_token"

    // MARK: - JWT Tokens

    static var accessToken: String? {
        get { load(key: accessKey) }
        set {
            if let value = newValue { save(value, key: accessKey) }
            else { delete(key: accessKey) }
        }
    }

    static var refreshToken: String? {
        get { load(key: refreshKey) }
        set {
            if let value = newValue { save(value, key: refreshKey) }
            else { delete(key: refreshKey) }
        }
    }

    // MARK: - APNs Device Token

    static var deviceToken: String? {
        get { load(key: deviceTokenKey) }
        set {
            if let value = newValue { save(value, key: deviceTokenKey) }
            else { delete(key: deviceTokenKey) }
        }
    }

    // MARK: - Convenience

    static func clearAll() {
        delete(key: accessKey)
        delete(key: refreshKey)
    }

    // MARK: - Private helpers

    private static func save(_ value: String, key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        let attrs: [CFString: Any] = [kSecValueData: data]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func load(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
