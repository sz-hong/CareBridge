import Foundation
import HealthKit

/// 把 Apple Watch / iPhone 的 HealthKit 資料增量同步到 backend。
///
/// 設計重點：
/// - **HKObserverQuery + Background Delivery**：watch 一寫進 HealthKit，iOS
///   會把 app 從背景叫起，呼叫 observer callback。
/// - **HKAnchoredObjectQuery + anchor 持久化**：每個 quantity type 都有自己
///   的 anchor，存在 UserDefaults 裡。每次只抓「上次同步點之後」的 delta。
/// - **冪等上傳**：backend 用 `(family, type, recorded_at)` unique，所以
///   重傳同一筆是 no-op。安全 retry。
/// - **Anchor 推進的順序**：先成功上傳再儲存 anchor，避免「上傳失敗但
///   anchor 已前進」造成資料漏。
@Observable
final class HealthKitSyncManager {

    // MARK: - Configuration

    /// 想同步的 HealthKit type → CareBridge wire type。
    /// 增加新的種類只要在這裡新增一行（並確保 backend `HealthData.Type` 也認得）。
    struct SyncedType {
        let hkIdentifier: HKQuantityTypeIdentifier
        let backendType: String
        let unit: HKUnit
        let backendUnit: String
        /// SpO2 / 血壓回傳的是 0-1 的小數，需要乘 100 轉成百分比。
        let scale: Double
    }

    private let syncedTypes: [SyncedType] = [
        SyncedType(hkIdentifier: .heartRate,
                   backendType: "heart_rate",
                   unit: HKUnit(from: "count/min"), backendUnit: "bpm",
                   scale: 1.0),
        SyncedType(hkIdentifier: .oxygenSaturation,
                   backendType: "blood_oxygen",
                   unit: .percent(), backendUnit: "%",
                   scale: 100.0),
        SyncedType(hkIdentifier: .stepCount,
                   backendType: "step_count",
                   unit: .count(), backendUnit: "steps",
                   scale: 1.0),
        SyncedType(hkIdentifier: .activeEnergyBurned,
                   backendType: "active_energy",
                   unit: .kilocalorie(), backendUnit: "kcal",
                   scale: 1.0),
        SyncedType(hkIdentifier: .bloodPressureSystolic,
                   backendType: "blood_pressure_systolic",
                   unit: .millimeterOfMercury(), backendUnit: "mmHg",
                   scale: 1.0),
        SyncedType(hkIdentifier: .bloodPressureDiastolic,
                   backendType: "blood_pressure_diastolic",
                   unit: .millimeterOfMercury(), backendUnit: "mmHg",
                   scale: 1.0),
    ]

    // MARK: - State

    private let store = HKHealthStore()
    private let service: DataService
    private let queue = HealthSampleUploadQueue()

    /// 這些 ObserverQuery 一旦註冊就要一直跑——存著避免被 GC。
    private var activeObservers: [HKObserverQuery] = []

    /// 上次同步是否成功。FE 可以拿來顯示連線狀態。
    var lastSyncedAt: Date?
    var lastError: String?

    // MARK: - Init

    init(service: DataService) {
        self.service = service
    }

    // MARK: - Public API

    /// 完整啟動流程：請求授權 → 開啟 background delivery → 註冊 observer。
    /// App 啟動或登入完成後呼叫一次即可。
    func startSyncing() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await requestAuthorization()
            try await enableBackgroundDelivery()
            startObservers()
            // 啟動時也 trigger 一次 incremental sync，補上離線期間的資料。
            await incrementalSyncAll()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 對所有 type 跑一次 anchored query，把 delta 上傳。
    /// 通常被 ObserverQuery 觸發，也可以手動呼叫。
    func incrementalSyncAll() async {
        for type in syncedTypes {
            await incrementalSync(for: type)
        }
        await flushPending()
    }

    // MARK: - Authorization

    private func requestAuthorization() async throws {
        let readTypes: Set<HKObjectType> = Set(
            syncedTypes.compactMap { HKQuantityType.quantityType(forIdentifier: $0.hkIdentifier) }
        )
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - Background Delivery

    private func enableBackgroundDelivery() async throws {
        for type in syncedTypes {
            guard let qt = HKQuantityType.quantityType(forIdentifier: type.hkIdentifier) else { continue }
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                store.enableBackgroundDelivery(for: qt, frequency: .immediate) { success, error in
                    if let error { cont.resume(throwing: error) }
                    else if success { cont.resume() }
                    else { cont.resume(throwing: SyncError.backgroundDeliveryFailed) }
                }
            }
        }
    }

    // MARK: - Observers

    private func startObservers() {
        for type in syncedTypes {
            guard let qt = HKQuantityType.quantityType(forIdentifier: type.hkIdentifier) else { continue }
            let observer = HKObserverQuery(sampleType: qt, predicate: nil) { [weak self] _, completionHandler, error in
                guard let self else { completionHandler(); return }
                if let error {
                    self.lastError = error.localizedDescription
                    completionHandler()
                    return
                }
                Task {
                    await self.incrementalSync(for: type)
                    await self.flushPending()
                    completionHandler()  // 必須呼叫，告訴 iOS 已處理完
                }
            }
            store.execute(observer)
            activeObservers.append(observer)
        }
    }

    // MARK: - Incremental Sync (anchored)

    private func incrementalSync(for type: SyncedType) async {
        guard let qt = HKQuantityType.quantityType(forIdentifier: type.hkIdentifier) else { return }
        let anchor = HealthAnchorStore.load(for: type.hkIdentifier)

        let (samples, newAnchor) = await runAnchored(query: qt, anchor: anchor)
        guard !samples.isEmpty || newAnchor != nil else { return }

        let items = samples.map { $0.toSyncItem(typeMap: type) }
        if !items.isEmpty {
            queue.enqueue(items)
        }

        // 推 anchor — 只在這裡推，等 flushPending 成功才真的安全推進。
        // 但如果 samples 為空，也可以推 anchor (代表已知無新資料)。
        if items.isEmpty, let newAnchor {
            HealthAnchorStore.save(newAnchor, for: type.hkIdentifier)
        }
        // 有 items 時，anchor 留到 flushPending 成功後再推。
        if !items.isEmpty, let newAnchor {
            queue.attachPendingAnchor(newAnchor, identifier: type.hkIdentifier)
        }
    }

    private func runAnchored(query qt: HKQuantityType, anchor: HKQueryAnchor?) async -> (samples: [HKQuantitySample], newAnchor: HKQueryAnchor?) {
        await withCheckedContinuation { cont in
            let q = HKAnchoredObjectQuery(
                type: qt,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit,
            ) { _, samples, _, newAnchor, _ in
                let qSamples = (samples as? [HKQuantitySample]) ?? []
                cont.resume(returning: (qSamples, newAnchor))
            }
            store.execute(q)
        }
    }

    // MARK: - Upload

    private func flushPending() async {
        guard !queue.pendingItems.isEmpty else { return }
        do {
            let result = try await service.syncHealthSamples(queue.pendingItems)
            // 上傳成功才 commit anchors
            queue.commitAnchors()
            queue.clear()
            await MainActor.run {
                lastSyncedAt = Date()
                lastError = nil
            }
            print("[HealthKitSync] uploaded synced=\(result.synced) duplicates=\(result.duplicates)")
        } catch {
            // 失敗：anchor 不前進，items 保留在 queue 裡，下次 retry。
            await MainActor.run { lastError = error.localizedDescription }
            print("[HealthKitSync] upload failed: \(error)")
        }
    }

    // MARK: - Errors

    enum SyncError: Error {
        case backgroundDeliveryFailed
    }
}

// MARK: - Anchor persistence (UserDefaults)

private enum HealthAnchorStore {
    private static let prefix = "carebridge.healthAnchor."

    static func load(for id: HKQuantityTypeIdentifier) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: prefix + id.rawValue) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    static func save(_ anchor: HKQueryAnchor, for id: HKQuantityTypeIdentifier) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: prefix + id.rawValue)
    }
}

// MARK: - Pending queue

/// In-memory pending uploads + the anchors that should advance once the
/// upload succeeds. Lives for the duration of the app process; on cold
/// start the anchored query simply re-fetches the same delta from
/// HealthKit (idempotent on backend side anyway).
private final class HealthSampleUploadQueue {
    private(set) var pendingItems: [HealthSyncItem] = []
    private var pendingAnchors: [(HKQuantityTypeIdentifier, HKQueryAnchor)] = []

    func enqueue(_ items: [HealthSyncItem]) {
        pendingItems.append(contentsOf: items)
    }

    func attachPendingAnchor(_ anchor: HKQueryAnchor, identifier: HKQuantityTypeIdentifier) {
        pendingAnchors.append((identifier, anchor))
    }

    func commitAnchors() {
        for (id, anchor) in pendingAnchors {
            HealthAnchorStore.save(anchor, for: id)
        }
        pendingAnchors.removeAll()
    }

    func clear() {
        pendingItems.removeAll()
    }
}

// MARK: - HKQuantitySample → HealthSyncItem

private extension HKQuantitySample {
    func toSyncItem(typeMap: HealthKitSyncManager.SyncedType) -> HealthSyncItem {
        // Backend stores DecimalField(max_digits=10, decimal_places=2) so we
        // must round to 2 dp here. HealthKit spits out 0.978333... for SpO2
        // which becomes 97.8333… after the *100 scale and would otherwise
        // get rejected as too-precise.
        let raw = quantity.doubleValue(for: typeMap.unit) * typeMap.scale
        let rounded = (raw * 100).rounded() / 100

        return HealthSyncItem(
            type: typeMap.backendType,
            value: rounded,
            unit: typeMap.backendUnit,
            recordedAt: endDate,
            deviceId: device?.name,
            source: device?.name?.lowercased().contains("watch") == true
                ? "apple_watch"
                : "iphone"
        )
    }
}
