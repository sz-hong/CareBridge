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

    init() {
        let service: DataService = APIDataService()
        dataService      = service
        _userStore       = State(initialValue: UserStore(service: service))
        _careLogStore    = State(initialValue: CareLogStore(service: service))
        _todoStore       = State(initialValue: TodoStore(service: service))
        _calendarStore   = State(initialValue: CalendarStore(service: service))
        _medicationStore = State(initialValue: MedicationStore(service: service))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isLoggedIn {
                    ContentView(isLoggedIn: $isLoggedIn, userRole: userRole)
                } else {
                    LoginView(isLoggedIn: $isLoggedIn, userRole: $userRole)
                }
            }
            .environment(userStore)
            .environment(careLogStore)
            .environment(todoStore)
            .environment(calendarStore)
            .environment(medicationStore)
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
