import SwiftUI
import UserNotifications
import SwiftData

@main
struct CareBridgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var isLoggedIn = false
    @State private var userRole: UserRole = .family

    private let dataService: DataService

    @State private var userStore: UserStore
    @State private var careLogStore: CareLogStore
    @State private var todoStore: TodoStore
    @State private var calendarStore: CalendarStore
    @State private var medicationStore: MedicationStore
    @State private var localeStore = LocaleStore()
    @State private var healthSync: HealthKitSyncManager
    @AppStorage("carebridge.healthSyncEnabled") private var healthSyncEnabled = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let service: DataService = APIDataService()
        dataService      = service
        _userStore       = State(initialValue: UserStore(service: service))
        _careLogStore    = State(initialValue: CareLogStore(service: service))
        _todoStore       = State(initialValue: TodoStore(service: service))
        _calendarStore   = State(initialValue: CalendarStore(service: service))
        _medicationStore = State(initialValue: MedicationStore(service: service))
        _healthSync      = State(initialValue: HealthKitSyncManager(service: service))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !isLoggedIn {
                    LoginView(isLoggedIn: $isLoggedIn, userRole: $userRole)
                } else if userStore.currentUser?.family == nil {
                    // 已登入但尚未加入/建立家庭
                    FamilySelectionView(isLoggedIn: $isLoggedIn, userRole: $userRole)
                } else {
                    ContentView(isLoggedIn: $isLoggedIn, userRole: userRole)
                        // Once user is logged in AND has a family, kick off
                        // HealthKit observers + background delivery. Re-runs
                        // are no-ops (HK Authorization is idempotent and
                        // observers replace the previous registration).
                        .task {
                            // 健康同步只在「本機標記開啟」且「後端 binding 還是
                            // 自己」時才啟動。其中第二個條件抓的是這個情境：
                            // 另一支裝置在你離線時 claim 走了 binding ——
                            // 這時本機再 startSyncing 也是徒勞（會 403），而且
                            // 還會誤導使用者以為仍在同步。
                            guard healthSyncEnabled else { return }
                            if let state = try? await dataService.fetchHealthBinding() {
                                if state.isOwner {
                                    await healthSync.startSyncing()
                                } else {
                                    healthSyncEnabled = false
                                }
                            }
                        }
                        // Trigger an explicit sync every time the app comes
                        // back to foreground. This is the reliable path on
                        // free Apple Developer accounts (no background
                        // delivery entitlement) — opening Apple Health app
                        // pushes data to HK; switching back to us picks it up.
                        .onChange(of: scenePhase) { _, newPhase in
                            if newPhase == .active, healthSyncEnabled {
                                Task {
                                    if let state = try? await dataService.fetchHealthBinding(), state.isOwner {
                                        await healthSync.incrementalSyncAll()
                                    } else {
                                        healthSyncEnabled = false
                                    }
                                }
                            }
                        }
                }
            }
            // The logged-in account's `language` is the source of truth for the
            // whole UI: chat AND every other screen read `localeStore.code`.
            // Sync it on login / account switch so switching accounts on one
            // device (or a stale device UI language) can't leave the reader
            // seeing chat translated into the wrong person's language.
            .onChange(of: userStore.currentUser?.language) { _, newLang in
                if let newLang,
                   SupportedLanguage.all.contains(where: { $0.code == newLang }),
                   newLang != localeStore.code {
                    localeStore.code = newLang
                }
            }
            .environment(userStore)
            .environment(careLogStore)
            .environment(todoStore)
            .environment(calendarStore)
            .environment(medicationStore)
            .environment(localeStore)
            .environment(healthSync)
            .environment(\.locale, localeStore.locale)
            .environment(\.dataService, dataService)
            .preferredColorScheme(.light)
        }
        // SwiftData 離線快取容器
        .modelContainer(for: [CachedExpense.self, CachedCareLogEntry.self, CachedMedication.self])
    }
}

// MARK: - APNs AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        return true
    }

    /// 成功取得 device token — 儲存至 Keychain 並上傳後端
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        KeychainService.deviceToken = token
        Task {
            try? await APIDataService().registerPushToken(token)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[APNs] 註冊失敗：\(error.localizedDescription)")
    }

    /// App 在前台時也顯示通知 banner
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions {
        [.banner, .badge, .sound]
    }
}

// MARK: - SwiftData 離線快取模型

/// 離線快取：消費記錄
@Model
class CachedExpense {
    @Attribute(.unique) var id: String
    var title: String
    var amount: Double
    var category: String
    var date: Date
    var syncedAt: Date

    init(id: String, title: String, amount: Double, category: String, date: Date) {
        self.id = id
        self.title = title
        self.amount = amount
        self.category = category
        self.date = date
        self.syncedAt = Date()
    }
}

/// 離線快取：照護日誌
@Model
class CachedCareLogEntry {
    @Attribute(.unique) var id: String
    var content: String
    var category: String
    var date: Date
    var syncedAt: Date

    init(id: String, content: String, category: String, date: Date) {
        self.id = id
        self.content = content
        self.category = category
        self.date = date
        self.syncedAt = Date()
    }
}

/// 離線快取：藥物
@Model
class CachedMedication {
    @Attribute(.unique) var id: String
    var name: String
    var dosage: String
    var times: [String]
    var syncedAt: Date

    init(id: String, name: String, dosage: String, times: [String]) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.times = times
        self.syncedAt = Date()
    }
}
