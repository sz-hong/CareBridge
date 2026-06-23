import Foundation

extension APIDataService {
    // MARK: - Health
    func fetchHealthData(elderId: String) async throws -> HealthData { try await get(path: APIEndpoint.healthDashboard) }
    func fetchWeeklySteps(elderId: String) async throws -> [Int] { try await get(path: APIEndpoint.healthWeeklySteps) }

    /// 過去 `days` 天的每日彙整趨勢（單一 type）。
    func fetchHealthHistory(type: String, days: Int) async throws -> [HealthHistoryPoint] {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -(days - 1), to: to) ?? to
        return try await get(path: APIEndpoint.healthHistory(
            type: type,
            dateFrom: fmt.string(from: from),
            dateTo: fmt.string(from: to),
        ))
    }

    /// 家庭的健康異常紀錄（最新在前）。
    func fetchHealthAlerts() async throws -> [HealthAlert] {
        try await get(path: APIEndpoint.healthAlerts)
    }

    func syncHealthSamples(_ samples: [HealthSyncItem]) async throws -> HealthSyncResult {
        // Backend expects {"data": [...]}; response envelope is unwrapped by APIClient.
        struct Body: Encodable { let data: [HealthSyncItem] }
        return try await post(path: APIEndpoint.healthSync, body: Body(data: samples))
    }

    // MARK: - Health Binding

    func fetchHealthBinding() async throws -> HealthBindingState {
        try await get(path: APIEndpoint.familyHealthBinding)
    }

    func claimHealthBinding(deviceId: String, deviceLabel: String?) async throws -> HealthBindingState {
        do {
            return try await post(
                path: APIEndpoint.familyHealthBinding,
                body: ClaimHealthBindingRequest(deviceId: deviceId, deviceLabel: deviceLabel),
            )
        } catch APIError.serverError(let code) where code == 409 {
            throw HealthBindingError.conflict
        } catch APIError.backendError(let code, _) where code == 409 {
            throw HealthBindingError.conflict
        }
    }

    func releaseHealthBinding() async throws -> HealthBindingState {
        // DELETE 的回應一樣回 binding state（已清空），所以這裡不能用基底
        // 的 `delete(path:)` —— 那個是 Void。改用泛型 request 直接拿 body。
        do {
            return try await request("DELETE", path: APIEndpoint.familyHealthBinding)
        } catch APIError.serverError(let code) where code == 403 {
            throw HealthBindingError.notOwner
        } catch APIError.backendError(let code, _) where code == 403 {
            throw HealthBindingError.notOwner
        }
    }

    func fetchHealthThresholds() async throws -> HealthAlertThresholdSettings {
        try await get(path: APIEndpoint.healthThresholds)
    }

    func updateHealthThresholds(_ thresholds: HealthAlertThresholdSettings) async throws -> HealthAlertThresholdSettings {
        try await put(path: APIEndpoint.healthThresholds, body: thresholds)
    }
}
