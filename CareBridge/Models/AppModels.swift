import SwiftUI
import Foundation
import UIKit

// MARK: - User Roles
enum UserRole: String, CaseIterable, Codable {
    case caregiver = "caregiver"
    case family = "family_member"
    case elder = "elder"

    var displayName: String {
        switch self {
        case .caregiver: return String(localized: "看護")
        case .family:    return String(localized: "家屬")
        case .elder:     return String(localized: "長者")
        }
    }
}

enum ExpenseRecordAccessContext {
    case allExpenses
    case recentTransactions
}

enum ExpenseRecordPermissions {
    static func canManageRecords(
        userRole: UserRole,
        context: ExpenseRecordAccessContext = .allExpenses
    ) -> Bool {
        userRole == .family && context == .allExpenses
    }
}

enum ExpenseRecordPresentation {
    static let recentTransactionLimit = 10

    static func recentTransactions(from expenses: [Expense]) -> [Expense] {
        Array(expenses.prefix(recentTransactionLimit))
    }
}

// MARK: - User Profile
struct FamilyInfo: Codable {
    var id: String
    var name: String
    var inviteCode: String?
}

struct UserProfile: Identifiable, Codable {
    var id: String
    var name: String
    var email: String
    var phone: String?
    var birthday: String?
    var language: String?
    var role: UserRole?          // nil until user joins or creates a family
    var avatarUrl: String?
    var family: FamilyInfo?
    var isPrimary: Bool?

    // Backward-compat computed properties used by views
    var familyId: String   { family?.id   ?? "" }
    var familyName: String { family?.name ?? "" }
    var familyInviteCode: String? { family?.inviteCode }
    var avatarURL: String? { avatarUrl }

    // MARK: Custom Coding
    // NOTE: APIDataService uses .convertFromSnakeCase, which auto-converts
    // JSON keys to camelCase BEFORE matching CodingKeys. So rawValues here
    // must be camelCase (the decoder sees "familyId" not "family_id").
    private enum CodingKeys: String, CodingKey {
        case id, name, email, phone, birthday, language, role
        case avatarUrl
        case isPrimary
        // flat fields from backend (JSON: family_id → auto-converted to familyId)
        case flatFamilyId         = "familyId"
        case flatFamilyName       = "familyName"
        case flatFamilyInviteCode = "familyInviteCode"
        // nested field (used by MockDataService / local cache)
        case family
    }

    init(id: String, name: String, email: String, phone: String? = nil,
         birthday: String? = nil, language: String? = nil,
         role: UserRole? = nil, avatarUrl: String? = nil,
         family: FamilyInfo? = nil, isPrimary: Bool? = nil) {
        self.id = id; self.name = name; self.email = email
        self.phone = phone; self.birthday = birthday; self.language = language
        self.role = role; self.avatarUrl = avatarUrl
        self.family = family; self.isPrimary = isPrimary
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(String.self, forKey: .id)
        name      = try c.decode(String.self, forKey: .name)
        email     = try c.decode(String.self, forKey: .email)
        phone     = try c.decodeIfPresent(String.self, forKey: .phone)
        birthday  = try c.decodeIfPresent(String.self, forKey: .birthday)
        language  = try c.decodeIfPresent(String.self, forKey: .language)
        role      = try c.decodeIfPresent(UserRole.self, forKey: .role)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        isPrimary = try c.decodeIfPresent(Bool.self, forKey: .isPrimary)

        // Try nested "family" first (MockDataService / local), fall back to flat fields
        if let nested = try? c.decodeIfPresent(FamilyInfo.self, forKey: .family) {
            family = nested
        } else if let fid = try? c.decodeIfPresent(String.self, forKey: .flatFamilyId),
                  let fname = try? c.decodeIfPresent(String.self, forKey: .flatFamilyName) {
            let invite = try? c.decodeIfPresent(String.self, forKey: .flatFamilyInviteCode)
            family = FamilyInfo(id: fid, name: fname, inviteCode: invite)
        } else {
            family = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(email, forKey: .email)
        try c.encodeIfPresent(phone, forKey: .phone)
        try c.encodeIfPresent(language, forKey: .language)
        try c.encodeIfPresent(role, forKey: .role)
        try c.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        try c.encodeIfPresent(isPrimary, forKey: .isPrimary)
        try c.encodeIfPresent(family, forKey: .family)
    }
}

// MARK: - Health Data
// Backend `/health-data/dashboard/` returns a dict keyed by metric type, e.g.
// {"heart_rate": {id, type, value, unit, recorded_at, ...},
//  "blood_oxygen": {...}, "step_count": {...}, ...}
// This struct flattens that dict into discrete typed fields for UI consumption.
struct HealthData: Identifiable, Codable {
    var id: String
    var heartRate: Int
    var bloodOxygen: Double
    var bloodPressureSystolic: Int
    var bloodPressureDiastolic: Int
    var bloodSugar: Double
    var temperature: Double
    var steps: Int
    var activeEnergy: Double
    var timestamp: Date
    var isAbnormal: Bool

    init(id: String, heartRate: Int, bloodOxygen: Double,
         bloodPressureSystolic: Int, bloodPressureDiastolic: Int,
         bloodSugar: Double, temperature: Double, steps: Int, activeEnergy: Double = 0,
         timestamp: Date, isAbnormal: Bool) {
        self.id = id; self.heartRate = heartRate; self.bloodOxygen = bloodOxygen
        self.bloodPressureSystolic = bloodPressureSystolic
        self.bloodPressureDiastolic = bloodPressureDiastolic
        self.bloodSugar = bloodSugar; self.temperature = temperature
        self.steps = steps; self.activeEnergy = activeEnergy
        self.timestamp = timestamp; self.isAbnormal = isAbnormal
    }

    private struct Entry: Codable {
        var id: String?
        var value: Double?
        var recordedAt: Date?
        enum CodingKeys: String, CodingKey {
            case id, value
            case recordedAt  // "recorded_at" → convertFromSnakeCase → "recordedAt"
        }
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String; var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        func entry(_ key: String) -> Entry? {
            guard let k = DynamicKey(stringValue: key) else { return nil }
            return try? c.decodeIfPresent(Entry.self, forKey: k)
        }
        let hr = entry("heartRate")    // API: heart_rate → convertFromSnakeCase → heartRate
        let ox = entry("bloodOxygen")  // API: blood_oxygen
        let st = entry("stepCount")    // API: step_count
        let ae = entry("activeEnergy") // API: active_energy
        heartRate   = hr?.value.map { Int($0) } ?? 0
        bloodOxygen = ox?.value ?? 0
        steps       = st?.value.map { Int($0) } ?? 0
        activeEnergy = ae?.value ?? 0
        // Backend HealthData has no blood pressure / sugar / temperature types in current schema
        bloodPressureSystolic = 0
        bloodPressureDiastolic = 0
        bloodSugar  = 0
        temperature = 0
        timestamp   = hr?.recordedAt ?? ox?.recordedAt ?? st?.recordedAt ?? ae?.recordedAt ?? Date()
        id          = hr?.id ?? ox?.id ?? st?.id ?? ae?.id ?? UUID().uuidString
        isAbnormal  = false
    }

    func encode(to encoder: Encoder) throws {
        // Read-only on client — dashboard endpoint is GET-only.
    }

    static var sample: HealthData {
        HealthData(
            id: UUID().uuidString,
            heartRate: 72,
            bloodOxygen: 97.5,
            bloodPressureSystolic: 118,
            bloodPressureDiastolic: 75,
            bloodSugar: 5.8,
            temperature: 36.5,
            steps: 2340,
            timestamp: Date(),
            isAbnormal: false
        )
    }

    static var weeklySteps: [Int] {
        [1800, 2400, 3100, 2700, 1500, 900, 2340]
    }
}

// MARK: - Flexible ISO8601 parsing

/// 後端 DRF 以 iso-8601 輸出，model datetime 常帶微秒（fractional seconds），
/// 但 `JSONDecoder.dateDecodingStrategy = .iso8601` 不吃微秒。健康趨勢/異常
/// 的時間欄位是必填、不能靜默 fallback 成 now，所以這裡用容錯解析器。
enum FlexibleISO8601 {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func date(from string: String) -> Date? {
        withFraction.date(from: string) ?? plain.date(from: string)
    }
}

// MARK: - Health History (daily-aggregated trend)

/// 一天的彙整讀數，對應後端 `GET /health-data/?aggregation=daily` 的單筆。
/// 來源是家庭範圍的後端資料，所以遠端家屬也能看到趨勢（不依賴本機 HealthKit）。
struct HealthHistoryPoint: Codable, Identifiable {
    let type: String
    let period: Date     // API: period（ISO8601 當日 00:00）
    let avgValue: Double // API: avg_value → convertFromSnakeCase → avgValue
    var id: Date { period }

    enum CodingKeys: String, CodingKey { case type, period, avgValue }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        avgValue = try c.decode(Double.self, forKey: .avgValue)
        let periodString = try c.decode(String.self, forKey: .period)
        guard let parsed = FlexibleISO8601.date(from: periodString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .period, in: c,
                debugDescription: "Unparseable ISO8601 date: \(periodString)")
        }
        period = parsed
    }
}

// MARK: - Health Alert (真實異常紀錄)

/// 後端 `HealthAlert` —— 數值超出家庭警戒值時自動建立。取代健康監測頁原本
/// 寫死的「異常紀錄」清單。
struct HealthAlert: Codable, Identifiable {
    let id: String
    let type: String       // heart_rate / blood_oxygen
    let value: Double
    let threshold: Double
    let severity: String   // warning / critical
    let recordedAt: Date
    let createdAt: Date
    let acknowledgedAt: Date?

    /// 是否已被某位家庭成員確認。
    var isAcknowledged: Bool { acknowledgedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id, type, value, threshold, severity, recordedAt, createdAt, acknowledgedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(String.self, forKey: .type)
        value = try c.decode(Double.self, forKey: .value)
        threshold = try c.decode(Double.self, forKey: .threshold)
        severity = try c.decode(String.self, forKey: .severity)
        recordedAt = FlexibleISO8601.date(
            from: (try? c.decode(String.self, forKey: .recordedAt)) ?? "") ?? Date()
        createdAt = FlexibleISO8601.date(
            from: (try? c.decode(String.self, forKey: .createdAt)) ?? "") ?? Date()
        if let ackString = try? c.decodeIfPresent(String.self, forKey: .acknowledgedAt) {
            acknowledgedAt = FlexibleISO8601.date(from: ackString)
        } else {
            acknowledgedAt = nil
        }
    }
}

// MARK: - Supported Languages
// Must stay aligned with backend `core.translation.SUPPORTED_LANGUAGES`.
enum SupportedLanguage {
    struct Option { let code: String; let displayName: String }

    static let all: [Option] = [
        Option(code: "zh-TW", displayName: "繁體中文"),
        Option(code: "id",    displayName: "Bahasa Indonesia"),
        Option(code: "vi",    displayName: "Tiếng Việt"),
        Option(code: "tl",    displayName: "Tagalog"),
    ]

    static func displayName(for code: String?) -> String {
        all.first { $0.code == code }?.displayName ?? "繁體中文"
    }

    /// Best-effort guess based on the device's preferred language list.
    /// Falls back to zh-TW when no supported match is found.
    static var defaultFromLocale: String {
        for raw in Locale.preferredLanguages {
            let lower = raw.lowercased()
            if lower.hasPrefix("zh") { return "zh-TW" }
            if lower.hasPrefix("id") { return "id" }
            if lower.hasPrefix("vi") { return "vi" }
            if lower.hasPrefix("tl") || lower.hasPrefix("fil") { return "tl" }
        }
        return "zh-TW"
    }

    /// Backend chat-translation code → iOS xcstrings locale identifier.
    /// `tl` has no UI translation yet; fall back to English.
    static func uiLocale(for chatCode: String?) -> Locale {
        switch chatCode {
        case "zh-TW", "zh-Hant": return Locale(identifier: "zh-Hant")
        case "id":               return Locale(identifier: "id")
        case "vi":               return Locale(identifier: "vi")
        case "tl":               return Locale(identifier: "en")  // 暫無 tl UI 翻譯
        default:                 return Locale(identifier: "zh-Hant")
        }
    }
}

// MARK: - Locale Store (UI 語言切換)
/// 跨整個 app 的 UI 語言開關。AppStorage 持久化，App 重啟仍記得。
/// 注意：UI 語言 code 跟 chat 翻譯 code 共用 SupportedLanguage 的值
/// （zh-TW / id / vi / tl），UI 渲染時會透過 `SupportedLanguage.uiLocale(for:)`
/// 對應到正確的 xcstrings locale。
@Observable
class LocaleStore {
    private let storageKey = "appLocaleCode"
    var code: String {
        didSet { UserDefaults.standard.set(code, forKey: storageKey) }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "appLocaleCode") {
            self.code = saved
        } else {
            self.code = SupportedLanguage.defaultFromLocale
        }
    }

    var locale: Locale { SupportedLanguage.uiLocale(for: code) }
}

// MARK: - Chat Message
struct ChatMessage: Identifiable, Codable {
    var id: String
    var sender: String          // API: sender.name
    var senderId: String?       // API: sender.id (used to dedupe our own echoes)
    var senderRole: UserRole    // local only (not from API)
    var content: String
    var translations: [String: String]?  // API: translations dict, keyed by lang code
    var timestamp: Date         // API: sent_at
    var isMe: Bool              // local only (not from API)
    var imageURL: String?
    var messageType: String?    // "text" | "purchase_request" | "leave_request"
    var referenceId: String?    // ID of the linked PurchaseRequest or LeaveRequest

    /// Returns translated text for the given language, or nil if it
    /// matches the original content (no point showing a duplicate).
    func translation(for language: String?) -> String? {
        guard let language, let dict = translations, let value = dict[language] else { return nil }
        return value == content ? nil : value
    }

    // MARK: Custom Coding (API field mapping)
    private enum CodingKeys: String, CodingKey {
        case id, content, translations, isMe, senderRole, imageURL
        case sender, messageType, referenceId
        case timestamp = "sentAt"   // API: sent_at → convertFromSnakeCase → sentAt
    }
    private enum SenderKeys: String, CodingKey { case name, id }

    init(id: String, sender: String, senderId: String? = nil, senderRole: UserRole,
         content: String, translations: [String: String]?, timestamp: Date,
         isMe: Bool, imageURL: String? = nil,
         messageType: String? = "text", referenceId: String? = nil) {
        self.id = id; self.sender = sender; self.senderId = senderId
        self.senderRole = senderRole
        self.content = content; self.translations = translations
        self.timestamp = timestamp; self.isMe = isMe; self.imageURL = imageURL
        self.messageType = messageType; self.referenceId = referenceId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(String.self, forKey: .id)
        content   = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        imageURL  = try c.decodeIfPresent(String.self, forKey: .imageURL)
        isMe      = (try? c.decodeIfPresent(Bool.self, forKey: .isMe)) ?? false
        senderRole = (try? c.decodeIfPresent(UserRole.self, forKey: .senderRole)) ?? .caregiver
        // Nested sender object → extract id and name
        if let senderC = try? c.nestedContainer(keyedBy: SenderKeys.self, forKey: .sender) {
            sender   = (try? senderC.decode(String.self, forKey: .name)) ?? ""
            senderId = try? senderC.decodeIfPresent(String.self, forKey: .id)
        } else {
            sender   = (try? c.decode(String.self, forKey: .sender)) ?? ""
            senderId = nil
        }
        translations = try? c.decodeIfPresent([String: String].self, forKey: .translations)
        messageType  = try? c.decodeIfPresent(String.self, forKey: .messageType)
        referenceId  = try? c.decodeIfPresent(String.self, forKey: .referenceId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(content, forKey: .content)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encodeIfPresent(imageURL, forKey: .imageURL)
        try c.encodeIfPresent(messageType, forKey: .messageType)
        try c.encodeIfPresent(referenceId, forKey: .referenceId)
    }

    static var samples: [ChatMessage] {
        [
            ChatMessage(id: UUID().uuidString, sender: "Rita Santos", senderRole: .caregiver,
                        content: "Sudah minum obat pagi.",
                        translations: ["zh-TW": "早上的藥已服用完畢。", "id": "Sudah minum obat pagi."],
                        timestamp: Date().addingTimeInterval(-3600), isMe: false),
            ChatMessage(id: UUID().uuidString, sender: "林小明", senderRole: .family,
                        content: "謝謝，今天狀況如何？",
                        translations: ["zh-TW": "謝謝，今天狀況如何？", "id": "Terima kasih, bagaimana keadaan hari ini?"],
                        timestamp: Date().addingTimeInterval(-3200), isMe: true),
            ChatMessage(id: UUID().uuidString, sender: "Rita Santos", senderRole: .caregiver,
                        content: "爺爺精神很好，有散步30分鐘。",
                        translations: ["zh-TW": "爺爺精神很好，有散步30分鐘。", "id": "Kakek semangat, sudah jalan 30 menit."],
                        timestamp: Date().addingTimeInterval(-3000), isMe: false),
            ChatMessage(id: UUID().uuidString, sender: "林大華", senderRole: .family,
                        content: "很好！晚上記得提醒他吃藥",
                        translations: nil,
                        timestamp: Date().addingTimeInterval(-2400), isMe: false),
        ]
    }
}

// MARK: - Chat Room
struct ChatRoom: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var participants: [String]       // API: members[].name
    var lastMessage: String          // API: last_message.content
    var lastMessageTime: Date        // API: last_message.sent_at
    var unreadCount: Int             // API: unread_count
    var isGroup: Bool                // API: type == "group"
    var avatarIcon: String           // local-only (UI)

    // MARK: Custom Coding (API field mapping)
    private enum CodingKeys: String, CodingKey {
        case id, name, type, members
        case lastMessage    // API: last_message → convertFromSnakeCase → lastMessage
        case unreadCount    // API: unread_count → unreadCount
    }
    private enum MemberKeys: String, CodingKey { case name }
    private enum LastMessageKeys: String, CodingKey {
        case content
        case sentAt     // API: sent_at → convertFromSnakeCase → sentAt
    }

    init(id: String, name: String, participants: [String], lastMessage: String,
         lastMessageTime: Date, unreadCount: Int, isGroup: Bool, avatarIcon: String) {
        self.id = id; self.name = name; self.participants = participants
        self.lastMessage = lastMessage; self.lastMessageTime = lastMessageTime
        self.unreadCount = unreadCount; self.isGroup = isGroup; self.avatarIcon = avatarIcon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(String.self, forKey: .id)
        name        = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        unreadCount = (try? c.decodeIfPresent(Int.self, forKey: .unreadCount)) ?? 0
        let type    = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "direct"
        isGroup     = (type == "group")
        avatarIcon  = isGroup ? "person.3.fill" : "person.fill"

        // members is [{id, name, role, avatar_url}] → extract names
        var names: [String] = []
        if var arr = try? c.nestedUnkeyedContainer(forKey: .members) {
            while !arr.isAtEnd {
                if let obj = try? arr.nestedContainer(keyedBy: MemberKeys.self),
                   let n = try? obj.decode(String.self, forKey: .name) {
                    names.append(n)
                } else {
                    _ = try? arr.decode(String.self)
                }
            }
        }
        participants = names

        // last_message: nullable dict with content + sent_at
        if let lm = try? c.nestedContainer(keyedBy: LastMessageKeys.self, forKey: .lastMessage) {
            lastMessage     = (try? lm.decode(String.self, forKey: .content)) ?? ""
            lastMessageTime = (try? lm.decode(Date.self, forKey: .sentAt)) ?? Date()
        } else {
            lastMessage = ""
            lastMessageTime = Date()
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(isGroup ? "group" : "direct", forKey: .type)
    }

    static var samples: [ChatRoom] {
        [
            ChatRoom(id: UUID().uuidString, name: "王家照護群", participants: ["林小明", "林大華", "Rita Santos"],
                     lastMessage: "爸爸今天血壓正常", lastMessageTime: Date().addingTimeInterval(-1200),
                     unreadCount: 3, isGroup: true, avatarIcon: "person.3.fill"),
            ChatRoom(id: UUID().uuidString, name: "Siti 小華", participants: ["林小明", "Siti"],
                     lastMessage: "已經吃過午餐了", lastMessageTime: Date().addingTimeInterval(-86400),
                     unreadCount: 0, isGroup: false, avatarIcon: "person.fill"),
        ]
    }
}

// MARK: - Care Log
enum CareLogType: String, CaseIterable, Codable {
    case medication = "medication"
    case vital      = "vital"
    case meal       = "meal"
    case activity   = "activity"
    case note       = "note"

    var displayName: LocalizedStringResource {
        switch self {
        case .medication: "用藥"
        case .vital:      "生命徵象"
        case .meal:       "飲食"
        case .activity:   "活動"
        case .note:       "備註"
        }
    }

    var displayNameKey: LocalizedStringKey {
        switch self {
        case .medication: "用藥"
        case .vital:      "生命徵象"
        case .meal:       "飲食"
        case .activity:   "活動"
        case .note:       "備註"
        }
    }

    var icon: String {
        switch self {
        case .medication: return "pills.fill"
        case .vital: return "heart.fill"
        case .meal: return "fork.knife"
        case .activity: return "figure.walk"
        case .note: return "note.text"
        }
    }

    var color: Color {
        switch self {
        case .medication: return Color("teal")
        case .vital: return .red
        case .meal: return .orange
        case .activity: return .green
        case .note: return .gray
        }
    }

    var uiColor: Color {
        switch self {
        case .medication: return Color(red: 0.0, green: 0.55, blue: 0.6)
        case .vital: return .red
        case .meal: return .orange
        case .activity: return .green
        case .note: return .gray
        }
    }
}

struct CareLogEntry: Identifiable, Codable {
    var id: String
    var type: CareLogType
    var title: String       // generated from API content JSONB
    var detail: String      // generated from API content JSONB
    var timestamp: Date     // API: timestamp
    var hasPhoto: Bool      // derived from photo_url != nil
    var photoURL: URL?
    var photoKey: String?
    /// Structured vitals — populated for .vital entries so views can read the
    /// latest reading without regex-parsing `detail`. All optional.
    var bloodPressureSystolic: Int? = nil
    var bloodPressureDiastolic: Int? = nil
    var bloodSugar: Double? = nil
    var temperature: Double? = nil
    var weight: Double? = nil
    /// API: content_translated — dict-of-dicts `{ fieldName: { lang: text } }`，
    /// 後端只翻譯 free-text 欄位（text / note / description / medication_name 等），
    /// 結構化數值（血壓、體溫）原樣保留。`displayDetail(language:)` 會用這個
    /// 字典覆寫對應欄位後重新拼成 detail 字串。
    var contentTranslations: [String: [String: String]]?
    /// 保留原始 raw content 給 display* 重新拼譯文用（避免重複解析 JSON）。
    fileprivate var rawContent: Content = Content()

    // MARK: Custom Coding
    private enum CodingKeys: String, CodingKey {
        case id, type, content, timestamp, contentTranslated
        case photoUrl   // API: photo_url → convertFromSnakeCase → photoUrl
        case photoKey
    }

    // Nested content fields (covers all care log types)
    fileprivate struct Content: Codable {
        var title: String?
        var medicationName: String?
        var dosage: String?
        var bloodPressureSystolic: Double?
        var bloodPressureDiastolic: Double?
        var bloodSugar: Double?
        var temperature: Double?
        var weight: Double?
        var note: String?
        var mealType: String?
        var description: String?
        var appetite: String?
        var activityType: String?
        var durationMinutes: Int?
        var text: String?
        var textTranslated: String?

        enum CodingKeys: String, CodingKey {
            // All snake_case keys auto-converted by .convertFromSnakeCase
            case title, medicationName, dosage, note, description, appetite, temperature, text
            case bloodPressureSystolic, bloodPressureDiastolic
            case bloodSugar, weight, mealType, activityType, durationMinutes, textTranslated
        }
    }

    init(id: String, type: CareLogType, title: String, detail: String,
         timestamp: Date, hasPhoto: Bool,
         photoURL: URL? = nil,
         photoKey: String? = nil,
         bloodPressureSystolic: Int? = nil,
         bloodPressureDiastolic: Int? = nil,
         bloodSugar: Double? = nil,
         temperature: Double? = nil,
         weight: Double? = nil) {
        self.id = id; self.type = type; self.title = title
        self.detail = detail; self.timestamp = timestamp
        self.photoURL = photoURL
        self.photoKey = photoKey
        self.hasPhoto = hasPhoto || photoURL != nil || photoKey != nil
        self.bloodPressureSystolic = bloodPressureSystolic
        self.bloodPressureDiastolic = bloodPressureDiastolic
        self.bloodSugar = bloodSugar
        self.temperature = temperature
        self.weight = weight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(String.self, forKey: .id)
        type      = try c.decode(CareLogType.self, forKey: .type)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        let photoURLString = try? c.decodeIfPresent(
            String.self,
            forKey: .photoUrl
        )
        photoURL = photoURLString.flatMap(URL.init(string:))
        photoKey = try? c.decodeIfPresent(String.self, forKey: .photoKey)
        hasPhoto = photoURL != nil || photoKey?.isEmpty == false

        let content = (try? c.decode(Content.self, forKey: .content)) ?? Content()
        // content_translated 是後端 keyDecodingStrategy 之外的特殊形狀
        // `{ field: { lang: text } }`，內層 lang key 帶連字號（zh-TW），
        // 不能再做 snake_case 轉換 —— 用 String 直接 decode 即可。
        contentTranslations = try? c.decodeIfPresent([String: [String: String]].self, forKey: .contentTranslated)
        rawContent = content

        // 設定 vital 結構化欄位（給 dashboard 直接讀）
        if let s = content.bloodPressureSystolic { bloodPressureSystolic = Int(s) }
        if let d = content.bloodPressureDiastolic { bloodPressureDiastolic = Int(d) }
        if let w = content.weight       { weight = w }
        if let bs = content.bloodSugar  { bloodSugar = bs }
        if let t = content.temperature  { temperature = t }

        // 原文版 title/detail —— 顯示時 view 呼叫 displayTitle/displayDetail
        // 取對應語言；沒翻譯就 fallback 到這裡。
        let built = CareLogEntry.build(type: type, content: content)
        title  = built.title
        detail = built.detail
    }

    /// 取對應語言的 title（用藥紀錄會翻 medication_name）。
    func displayTitle(language: String?) -> String {
        let translated = translatedContent(language: language)
        return CareLogEntry.build(
            type: type,
            content: translated,
            language: language
        ).title
    }

    /// 取對應語言的 detail（meal description / activity note / vital note / text 都會翻）。
    func displayDetail(language: String?) -> String {
        let translated = translatedContent(language: language)
        return CareLogEntry.build(
            type: type,
            content: translated,
            language: language
        ).detail
    }

    private func translatedContent(language: String?) -> Content {
        var copy = rawContent
        guard let language, let map = contentTranslations else { return copy }
        func pick(_ field: String, _ original: String?) -> String? {
            guard let original else { return nil }
            if let translated = map[field]?[language], !translated.isEmpty {
                return translated
            }
            return original
        }
        copy.medicationName = pick("medication_name", copy.medicationName)
        copy.title          = pick("title", copy.title)
        copy.note           = pick("note", copy.note)
        copy.description    = pick("description", copy.description)
        copy.text           = pick("text", copy.text)
        return copy
    }

    private static func build(
        type: CareLogType,
        content: Content,
        language: String? = nil
    ) -> (title: String, detail: String) {
        switch type {
        case .medication:
            return (
                title: content.medicationName
                    ?? localized("用藥紀錄", fallback: "用藥紀錄", language: language),
                detail: [content.dosage, content.note].compactMap { $0 }.joined(separator: "｜")
            )
        case .vital:
            var parts: [String] = []
            if let s = content.bloodPressureSystolic, let d = content.bloodPressureDiastolic {
                let label = localized("血壓", fallback: "血壓", language: language)
                parts.append("\(label) \(Int(s))/\(Int(d)) mmHg")
            }
            if let w = content.weight {
                let label = localized("體重", fallback: "體重", language: language)
                parts.append("\(label) \(w.formatted(.number.precision(.fractionLength(1)))) kg")
            }
            if let bs = content.bloodSugar {
                let label = localized("血糖", fallback: "血糖", language: language)
                parts.append("\(label) \(bs.formatted(.number.precision(.fractionLength(1)))) mmol/L")
            }
            if let t = content.temperature {
                let label = localized("體溫", fallback: "體溫", language: language)
                parts.append("\(label) \(t.formatted(.number.precision(.fractionLength(1))))°C")
            }
            if let n = content.note { parts.append(n) }
            return (
                title: localized(
                    "生理指標測量",
                    fallback: "生理指標測量",
                    language: language
                ),
                detail: parts.joined(separator: "｜")
            )
        case .meal:
            let descriptionTitle = content.description?
                .components(separatedBy: "｜")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let mealType = localizedStructuredValue(
                content.mealType,
                language: language
            )
            let appetite = localizedStructuredValue(
                content.appetite,
                language: language
            )
            return (
                title: content.title
                    ?? (descriptionTitle?.isEmpty == false ? descriptionTitle : nil)
                    ?? mealType
                    ?? localized("飲食紀錄", fallback: "飲食紀錄", language: language),
                detail: [
                    content.description,
                    appetite.map {
                        let label = localized("食慾", fallback: "食慾", language: language)
                        return "\(label)：\($0)"
                    },
                ]
                .compactMap { $0 }
                .joined(separator: "｜")
            )
        case .activity:
            let activityType = localizedStructuredValue(
                content.activityType,
                language: language
            )
            return (
                title: content.title
                    ?? activityType
                    ?? localized("活動紀錄", fallback: "活動紀錄", language: language),
                detail: content.durationMinutes.map {
                    localized(
                        "持續 \($0) 分鐘",
                        fallback: "持續 \($0) 分鐘",
                        language: language
                    )
                } ?? (content.note ?? "")
            )
        case .note:
            return (
                title: localized("備註", fallback: "備註", language: language),
                detail: content.text ?? content.textTranslated ?? ""
            )
        }
    }

    private static func localized(
        _ key: String.LocalizationValue,
        fallback: String,
        language: String?
    ) -> String {
        guard let language else { return fallback }
        let localeIdentifier = language == "tl" ? "fil" : language
        return String(
            localized: key,
            locale: Locale(identifier: localeIdentifier)
        )
    }

    private static func localizedStructuredValue(
        _ value: String?,
        language: String?
    ) -> String? {
        guard let value else { return nil }
        switch value.lowercased() {
        case "早餐", "breakfast":
            return localized("早餐", fallback: value, language: language)
        case "午餐", "lunch":
            return localized("午餐", fallback: value, language: language)
        case "晚餐", "dinner":
            return localized("晚餐", fallback: value, language: language)
        case "點心", "snack":
            return localized("點心", fallback: value, language: language)
        case "差", "poor":
            return localized("差", fallback: value, language: language)
        case "一般", "normal":
            return localized("一般", fallback: value, language: language)
        case "良好", "good":
            return localized("良好", fallback: value, language: language)
        case "輕度", "light":
            return localized("輕度", fallback: value, language: language)
        case "中度", "moderate":
            return localized("中度", fallback: value, language: language)
        case "高強度", "high":
            return localized("高強度", fallback: value, language: language)
        default:
            return value
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encodeIfPresent(photoKey, forKey: .photoKey)
        // Encode minimal content based on type. AnyCodable-free: use a mixed dict
        // so numeric vitals stay numeric instead of being stringified.
        var content: [String: AnyEncodable] = [:]
        switch type {
        case .note:       content["text"]        = AnyEncodable(detail)
        case .vital:
            // Vital structured fields go to dedicated keys. We **deliberately**
            // do NOT put `detail` into `note` — the decoder rebuilds the same
            // text from those keys, so writing it here would duplicate every
            // line on read-back.
            if let s = bloodPressureSystolic  { content["blood_pressure_systolic"]  = AnyEncodable(s) }
            if let d = bloodPressureDiastolic { content["blood_pressure_diastolic"] = AnyEncodable(d) }
            if let w  = weight       { content["weight"]      = AnyEncodable(w) }
            if let bs = bloodSugar   { content["blood_sugar"] = AnyEncodable(bs) }
            if let t  = temperature  { content["temperature"] = AnyEncodable(t) }
        case .meal:
            content["title"] = AnyEncodable(title)
            content["description"] = AnyEncodable(detail)
        case .activity:
            content["title"] = AnyEncodable(title)
            content["note"] = AnyEncodable(detail)
        case .medication: content["medication_name"] = AnyEncodable(title)
        }
        try c.encode(content, forKey: .content)
    }

    static var samples: [CareLogEntry] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        return [
            CareLogEntry(id: UUID().uuidString, type: .vital, title: "晨間生理指標測量",
                         detail: "血壓 118/75 mmHg｜心率 72 bpm",
                         timestamp: today.addingTimeInterval(8.5 * 3600), hasPhoto: false),
            CareLogEntry(id: UUID().uuidString, type: .medication, title: "晨間用藥提醒",
                         detail: "阿斯匹靈 (100mg) - 飯後服用",
                         timestamp: today.addingTimeInterval(8 * 3600 + 300), hasPhoto: false),
            CareLogEntry(id: UUID().uuidString, type: .meal, title: "營養早餐",
                         detail: "白粥、蒸蛋、菠菜，食慾良好，全部完食",
                         timestamp: today.addingTimeInterval(7.5 * 3600), hasPhoto: true),
            CareLogEntry(id: UUID().uuidString, type: .activity, title: "晨間散步",
                         detail: "花園散步 30 分鐘，約 1,200 步，狀態良好",
                         timestamp: today.addingTimeInterval(7 * 3600), hasPhoto: false),
            CareLogEntry(id: UUID().uuidString, type: .note, title: "晚間就寢紀錄",
                         detail: "21:00 安靜入睡，無異常",
                         timestamp: yesterday.addingTimeInterval(21 * 3600), hasPhoto: false),
        ]
    }
}

// MARK: - User Store (current user + family members)
private struct UserStoreData {
    var currentUser: UserProfile?
    var familyMembers: [UserProfile] = []
}

@Observable
class UserStore {
    private var state = AsyncViewState<UserStoreData>(
        value: UserStoreData(currentUser: nil)
    )
    private let service: DataService

    init(service: DataService = MockDataService()) { self.service = service }

    var currentUser: UserProfile? {
        get { state.value.currentUser }
        set {
            state.updateValue { data in
                data.currentUser = newValue
            }
        }
    }

    var familyMembers: [UserProfile] {
        get { state.value.familyMembers }
        set {
            state.updateValue { data in
                data.familyMembers = newValue
            }
        }
    }

    var isLoading: Bool { state.isLoading }
    var errorMessage: String? { state.errorMessage }

    /// Called immediately after login -- pre-populates profile from AuthResponse.
    func populate(from authResponse: AuthResponse) {
        state.updateValue { data in
            data.currentUser = authResponse.user
        }
    }

    func clearSession() {
        state.finish(with: UserStoreData(currentUser: nil, familyMembers: []))
    }

    /// Fire-and-forget compatibility wrapper for existing SwiftUI call sites.
    func load() {
        Task { @MainActor in
            await reload()
        }
    }

    /// Fetches up-to-date profile + family members from API.
    @MainActor
    func reload() async {
        guard !isLoading else { return }
        state.beginLoading()
        do {
            async let profile = service.fetchProfile()
            async let members = service.fetchFamilyMembers()
            let (p, m) = try await (profile, members)
            state.finish(with: UserStoreData(currentUser: p, familyMembers: m))
        } catch {
            state.fail(error)
            print("[UserStore] fetch failed: \(error)")
        }
    }
}

// MARK: - Care Log Store (shared state → API synced)
@Observable
class CareLogStore {
    private var state = AsyncViewState<[CareLogEntry]>(value: [])
    private var timelineState = AsyncViewState<[CareLogEntry]>(value: [])
    private let service: DataService
    @ObservationIgnored private var timelineCache: [TimelineQuery: TimelinePage] = [:]
    @ObservationIgnored private var activeTimelineQuery: TimelineQuery?
    @ObservationIgnored private var activeTimelineRequestID: UUID?
    private var didLoadRecentEntries = false
    private(set) var isLoadingMoreTimeline = false
    private(set) var timelineHasMore = false

    private struct TimelineQuery: Hashable {
        let day: Date
        let type: CareLogType?
    }

    private struct TimelinePage {
        var entries: [CareLogEntry]
        var nextPage: Int?
        var totalCount: Int
    }

    var entries: [CareLogEntry] {
        get { state.value }
        set { state.finish(with: newValue) }
    }

    var isLoading: Bool { state.isLoading }
    var errorMessage: String? { state.errorMessage }
    var timelineEntries: [CareLogEntry] { timelineState.value }
    var isTimelineLoading: Bool { timelineState.isLoading }
    var timelineErrorMessage: String? { timelineState.errorMessage }

    init(service: DataService = MockDataService()) {
        self.service = service
    }

    func load() {
        Task { @MainActor in
            await loadRecentEntries(forceRefresh: false)
        }
    }

    @MainActor
    func refreshRecentEntries() async {
        await loadRecentEntries(forceRefresh: true)
    }

    @MainActor
    func loadTimeline(
        date: Date,
        type: CareLogType?,
        forceRefresh: Bool = false
    ) async {
        let query = timelineQuery(date: date, type: type)
        let isSameQuery = activeTimelineQuery == query
        let previousEntries = isSameQuery ? timelineState.value : []
        let previousHasMore = isSameQuery ? timelineHasMore : false
        let requestID = UUID()

        activeTimelineQuery = query
        activeTimelineRequestID = requestID

        if !forceRefresh, let cached = timelineCache[query] {
            activeTimelineRequestID = nil
            applyTimelinePage(cached)
            return
        }

        timelineState.finish(with: previousEntries)
        timelineState.beginLoading()
        isLoadingMoreTimeline = false
        timelineHasMore = previousHasMore

        do {
            let result = try await service.fetchCareLogEntries(
                date: query.day,
                type: query.type,
                page: 1
            )
            guard !Task.isCancelled else {
                finishCancelledTimelineRequest(
                    query: query,
                    requestID: requestID,
                    previousEntries: previousEntries,
                    previousHasMore: previousHasMore
                )
                return
            }
            guard activeTimelineQuery == query,
                  activeTimelineRequestID == requestID else {
                return
            }
            let page = TimelinePage(
                entries: result.items,
                nextPage: result.hasNextPage ? 2 : nil,
                totalCount: result.totalCount
            )
            activeTimelineRequestID = nil
            timelineCache[query] = page
            applyTimelinePage(page)
        } catch {
            guard activeTimelineQuery == query,
                  activeTimelineRequestID == requestID else {
                return
            }
            activeTimelineRequestID = nil
            if Task.isCancelled || Self.isCancellation(error) {
                timelineState.finish(with: previousEntries)
                timelineHasMore = previousHasMore
                return
            }
            timelineState.fail(error)
            print("[CareLogStore] timeline fetch failed: \(error)")
        }
    }

    @MainActor
    func loadMoreTimeline() async {
        guard !isTimelineLoading,
              !isLoadingMoreTimeline,
              let query = activeTimelineQuery,
              var cached = timelineCache[query],
              let pageNumber = cached.nextPage else {
            return
        }

        isLoadingMoreTimeline = true
        defer {
            if activeTimelineQuery == query {
                isLoadingMoreTimeline = false
            }
        }

        do {
            let result = try await service.fetchCareLogEntries(
                date: query.day,
                type: query.type,
                page: pageNumber
            )
            guard !Task.isCancelled, activeTimelineQuery == query else {
                return
            }

            let existingIDs = Set(cached.entries.map(\.id))
            cached.entries.append(
                contentsOf: result.items.filter { !existingIDs.contains($0.id) }
            )
            cached.nextPage = result.hasNextPage ? pageNumber + 1 : nil
            cached.totalCount = result.totalCount
            timelineCache[query] = cached
            applyTimelinePage(cached)
        } catch {
            guard activeTimelineQuery == query else { return }
            if Task.isCancelled || Self.isCancellation(error) {
                return
            }
            timelineState.fail(error)
            timelineHasMore = false
            print("[CareLogStore] load more failed: \(error)")
        }
    }

    func hasEntry(on date: Date) -> Bool {
        let calendar = Calendar.current
        if state.value.contains(where: {
            calendar.isDate($0.timestamp, inSameDayAs: date)
        }) {
            return true
        }
        return timelineCache.values.contains { page in
            page.entries.contains {
                calendar.isDate($0.timestamp, inSameDayAs: date)
            }
        }
    }

    @MainActor
    func addEntry(_ entry: CareLogEntry, photo: UIImage?) async throws {
        var requestEntry = entry
        if let photo {
            let uploaded = try await service.uploadCareLogPhoto(photo)
            requestEntry.photoKey = uploaded.photoKey
            requestEntry.hasPhoto = true
        }
        let saved = try await service.createCareLogEntry(requestEntry)
        state.updateValue { entries in
            entries.insert(saved, at: 0)
        }
        didLoadRecentEntries = true

        let calendar = Calendar.current
        for query in Array(timelineCache.keys) {
            guard calendar.isDate(saved.timestamp, inSameDayAs: query.day),
                  query.type == nil || query.type == saved.type,
                  var page = timelineCache[query] else {
                continue
            }
            page.entries.removeAll { $0.id == saved.id }
            page.entries.insert(saved, at: 0)
            page.totalCount += 1
            timelineCache[query] = page
            if activeTimelineQuery == query {
                applyTimelinePage(page)
            }
        }
    }

    func deleteEntry(id: String) {
        let originalEntries = state.value
        let originalTimelineEntries = timelineState.value
        let originalTimelineCache = timelineCache
        let originalTimelineHasMore = timelineHasMore

        state.updateValue { entries in
            entries.removeAll { $0.id == id }
        }
        timelineState.updateValue { entries in
            entries.removeAll { $0.id == id }
        }
        for query in Array(timelineCache.keys) {
            guard var page = timelineCache[query] else { continue }
            let beforeCount = page.entries.count
            page.entries.removeAll { $0.id == id }
            if page.entries.count != beforeCount {
                page.totalCount = max(0, page.totalCount - (beforeCount - page.entries.count))
                timelineCache[query] = page
            }
        }

        Task { @MainActor in
            do {
                try await service.deleteCareLogEntry(id: id)
            } catch {
                print("[CareLogStore] delete failed: \(error)")
                state.finish(with: originalEntries)
                timelineState.finish(with: originalTimelineEntries)
                timelineCache = originalTimelineCache
                timelineHasMore = originalTimelineHasMore
            }
        }
    }

    private func timelineQuery(
        date: Date,
        type: CareLogType?
    ) -> TimelineQuery {
        TimelineQuery(
            day: Calendar.current.startOfDay(for: date),
            type: type
        )
    }

    @MainActor
    private func loadRecentEntries(forceRefresh: Bool) async {
        guard !isLoading else { return }
        guard forceRefresh || !didLoadRecentEntries else { return }

        state.beginLoading()
        do {
            let page = try await service.fetchCareLogEntries(
                date: nil,
                type: nil,
                page: 1
            )
            state.finish(with: page.items)
            didLoadRecentEntries = true
        } catch {
            state.fail(error)
            print("[CareLogStore] fetch failed: \(error)")
        }
    }

    private func applyTimelinePage(_ page: TimelinePage) {
        timelineState.finish(with: page.entries)
        timelineHasMore = page.nextPage != nil
        if let activeTimelineQuery {
            mergeTimelineEntriesIntoRecentEntries(page.entries, for: activeTimelineQuery)
        }
    }

    private func mergeTimelineEntriesIntoRecentEntries(
        _ timelineEntries: [CareLogEntry],
        for query: TimelineQuery
    ) {
        let calendar = Calendar.current
        state.updateValue { entries in
            entries.removeAll { entry in
                calendar.isDate(entry.timestamp, inSameDayAs: query.day)
                    && (query.type == nil || entry.type == query.type)
            }
            entries.append(contentsOf: timelineEntries)

            var seenIDs = Set<String>()
            entries = entries
                .sorted { $0.timestamp > $1.timestamp }
                .filter { seenIDs.insert($0.id).inserted }
        }
    }

    private func finishCancelledTimelineRequest(
        query: TimelineQuery,
        requestID: UUID,
        previousEntries: [CareLogEntry],
        previousHasMore: Bool
    ) {
        guard activeTimelineQuery == query,
              activeTimelineRequestID == requestID else {
            return
        }
        activeTimelineRequestID = nil
        timelineState.finish(with: previousEntries)
        timelineHasMore = previousHasMore
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
            && nsError.code == NSURLErrorCancelled
    }
}

// MARK: - Todo Store (shared state → API synced)
@Observable
class TodoStore {
    private var state = AsyncViewState<[TodoItem]>(value: [])
    private let service: DataService

    var todos: [TodoItem] {
        get { state.value }
        set { state.finish(with: newValue) }
    }

    var isLoading: Bool { state.isLoading }
    var errorMessage: String? { state.errorMessage }

    init(service: DataService = MockDataService()) {
        self.service = service
    }

    func load() {
        guard !isLoading else { return }
        state.beginLoading()
        Task { @MainActor in
            do {
                state.finish(with: try await service.fetchTodos())
            } catch {
                state.fail(error)
                print("[TodoStore] fetch failed: \(error)")
            }
        }
    }

    func addTodo(_ todo: TodoItem) {
        // Optimistic insert with the locally-generated UUID for instant UI
        // feedback. The backend ignores the wire `id` and assigns its own,
        // so we must reconcile by replacing the local copy with the server's
        // response — otherwise later updates PUT a non-existent id → 404.
        let optimistic = todo
        state.updateValue { todos in
            todos.insert(optimistic, at: 0)
        }
        Task { @MainActor in
            do {
                let saved = try await service.createTodo(optimistic)
                if let idx = todos.firstIndex(where: { $0.id == optimistic.id }) {
                    state.updateValue { todos in
                        todos[idx] = saved
                    }
                }
            } catch {
                print("[TodoStore] create failed: \(error)")
                state.updateValue { todos in
                    todos.removeAll { $0.id == optimistic.id }
                }
            }
        }
    }

    func updateTodo(_ todo: TodoItem) {
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            state.updateValue { todos in
                todos[index] = todo
            }
        }
        Task {
            do {
                _ = try await service.updateTodo(todo)
            } catch {
                print("[TodoStore] update failed: \(error)")
            }
        }
    }

    func deleteTodo(_ todo: TodoItem) {
        let originalTodos = todos
        state.updateValue { todos in
            todos.removeAll { $0.id == todo.id }
        }
        Task { @MainActor in
            do {
                try await service.deleteTodo(id: todo.id)
            } catch {
                print("[TodoStore] delete failed: \(error)")
                state.finish(with: originalTodos)
            }
        }
    }
}

// MARK: - Calendar Store (shared state → API synced)
@Observable
class CalendarStore {
    private var state = AsyncViewState<[CalendarEvent]>(value: [])
    private let service: DataService

    var events: [CalendarEvent] {
        get { state.value }
        set { state.finish(with: newValue) }
    }

    var isLoading: Bool { state.isLoading }
    var errorMessage: String? { state.errorMessage }

    init(service: DataService = MockDataService()) {
        self.service = service
    }

    func load() {
        guard !isLoading else { return }
        state.beginLoading()
        Task { @MainActor in
            do {
                state.finish(with: try await service.fetchCalendarEvents(month: Date()))
            } catch {
                state.fail(error)
                print("[CalendarStore] fetch failed: \(error)")
            }
        }
    }

    func addEvent(_ event: CalendarEvent) {
        // Optimistic insert with the local UUID for instant UI; the backend
        // ignores the wire id and assigns its own, so reconcile by swapping
        // the local copy with the server's response. Otherwise any later
        // update/delete would target a non-existent id → 404.
        let optimistic = event
        state.updateValue { events in
            events.append(optimistic)
        }
        Task { @MainActor in
            do {
                let saved = try await service.createCalendarEvent(optimistic)
                state.updateValue { events in
                    if let idx = events.firstIndex(where: { $0.id == optimistic.id }) {
                        events[idx] = saved
                    }
                }
            } catch {
                print("[CalendarStore] create failed: \(error)")
                state.updateValue { events in
                    events.removeAll { $0.id == optimistic.id }
                }
            }
        }
    }

    func addEvents(_ newEvents: [CalendarEvent]) {
        // Same reconciliation as `addEvent` but for batch posts. We match
        // server-returned events back to their local optimistic counterparts
        // by **position** in the request order — the backend preserves it.
        let optimistic = newEvents
        state.updateValue { events in
            events.append(contentsOf: optimistic)
        }
        Task { @MainActor in
            do {
                let saved = try await service.createCalendarEvents(optimistic)
                state.updateValue { events in
                    for (i, opt) in optimistic.enumerated() where i < saved.count {
                        if let idx = events.firstIndex(where: { $0.id == opt.id }) {
                            events[idx] = saved[i]
                        }
                    }
                }
            } catch {
                print("[CalendarStore] batch create failed: \(error)")
                let optimisticIds = Set(optimistic.map(\.id))
                state.updateValue { events in
                    events.removeAll { optimisticIds.contains($0.id) }
                }
            }
        }
    }
}

// MARK: - Medication Store (shared state → API synced)
@Observable
class MedicationStore {
    private var state = AsyncViewState<[Medication]>(value: [])
    var doses: [DoseEntry] = []
    private let service: DataService

    var medications: [Medication] {
        get { state.value }
        set { state.finish(with: newValue) }
    }

    var isLoading: Bool { state.isLoading }
    var errorMessage: String? { state.errorMessage }

    init(service: DataService = MockDataService()) {
        self.service = service
    }

    func load() {
        guard !isLoading else { return }
        state.beginLoading()
        Task { @MainActor in
            do {
                async let medsTask = service.fetchMedications(elderId: "")
                async let confsTask = service.fetchTodayConfirmations()
                let (fetchedMeds, confs) = try await (medsTask, confsTask)
                state.finish(with: fetchedMeds)
                
                // Build today's dose timeline
                var newDoses: [DoseEntry] = []
                for med in fetchedMeds {
                    for time in med.times {
                        let isConfirmed = confs.contains { $0.medication == med.id && $0.scheduledTime == time }
                        newDoses.append(DoseEntry(medicationId: med.id, time: time, name: "\(med.nameTranslated) \(med.dosage)", isDone: isConfirmed))
                    }
                }
                // Sort chronologically (e.g. 08:00 before 20:00)
                doses = newDoses.sorted { $0.time < $1.time }
                
            } catch {
                state.fail(error)
                print("[MedicationStore] fetch failed: \(error)")
            }
        }
    }

    func addMedication(_ medication: Medication) {
        // Optimistic insert (instant UI). 透過 setter 賦值整個陣列來觸發
        // @Observable 的變更通知 —— 直接 mutating state 在某些情況下不會
        // 通知到外層 SwiftUI 視圖，導致使用者要退出再進入才看得到新藥。
        let optimistic = medication
        var updatedList = medications
        updatedList.append(optimistic)
        medications = updatedList

        for time in optimistic.times {
            doses.append(DoseEntry(
                medicationId: optimistic.id, time: time,
                name: "\(optimistic.nameTranslated) \(optimistic.dosage)",
                isDone: false
            ))
        }
        doses.sort { $0.time < $1.time }

        Task { @MainActor in
            do {
                let saved = try await service.createMedication(optimistic)
                var swapped = medications
                if let idx = swapped.firstIndex(where: { $0.id == optimistic.id }) {
                    swapped[idx] = saved
                    medications = swapped
                }
                // Rewrite any dose entries that still reference the local id.
                for i in doses.indices where doses[i].medicationId == optimistic.id {
                    doses[i] = DoseEntry(
                        medicationId: saved.id,
                        time: doses[i].time,
                        name: doses[i].name,
                        isDone: doses[i].isDone
                    )
                }
            } catch {
                print("[MedicationStore] create failed: \(error)")
                medications = medications.filter { $0.id != optimistic.id }
                doses.removeAll { $0.medicationId == optimistic.id }
            }
        }
    }

    func updateMedication(_ medication: Medication) {
        let originalMedications = medications
        let originalDoses = doses
        var preservedDoseState: [String: Bool] = [:]
        for dose in doses where dose.medicationId == medication.id {
            preservedDoseState[dose.time] = dose.isDone
        }

        if let index = medications.firstIndex(where: { $0.id == medication.id }) {
            var updatedList = medications
            updatedList[index] = medication
            medications = updatedList
        }

        doses.removeAll { $0.medicationId == medication.id }
        for time in medication.times {
            doses.append(DoseEntry(
                medicationId: medication.id,
                time: time,
                name: "\(medication.nameTranslated) \(medication.dosage)",
                isDone: preservedDoseState[time] ?? false
            ))
        }
        doses.sort { $0.time < $1.time }

        Task { @MainActor in
            do {
                let saved = try await service.updateMedication(medication)
                if let index = medications.firstIndex(where: { $0.id == medication.id }) {
                    var updatedList = medications
                    updatedList[index] = saved
                    medications = updatedList
                }

                var currentDoseState: [String: Bool] = [:]
                for dose in doses where dose.medicationId == medication.id {
                    currentDoseState[dose.time] = dose.isDone
                }
                doses.removeAll { $0.medicationId == medication.id }
                for time in saved.times {
                    doses.append(DoseEntry(
                        medicationId: saved.id,
                        time: time,
                        name: "\(saved.nameTranslated) \(saved.dosage)",
                        isDone: currentDoseState[time] ?? false
                    ))
                }
                doses.sort { $0.time < $1.time }
            } catch {
                print("[MedicationStore] update failed: \(error)")
                medications = originalMedications
                doses = originalDoses
            }
        }
    }

    func markDoseTaken(index: Int) {
        guard index < doses.count, !doses[index].isDone else { return }
        // Optimistic flip for instant UI feedback. Capture the dose's stable
        // UUID before the network call so we can revert exactly the same row
        // even if `doses` was reordered or rebuilt by a concurrent reload.
        let doseId = doses[index].id
        let dose = doses[index]
        doses[index].isDone = true
        let request = ConfirmMedicationRequest(
            scheduledTime: dose.time, photoUrl: nil, note: nil
        )
        Task { @MainActor in
            do {
                _ = try await service.confirmMedication(
                    id: dose.medicationId, request: request
                )
            } catch {
                print("[MedicationStore] mark dose taken failed: \(error)")
                // Rollback the optimistic check so the UI matches reality.
                if let idx = doses.firstIndex(where: { $0.id == doseId }) {
                    doses[idx].isDone = false
                }
            }
        }
    }

    func deleteMedication(id: String) {
        let originalMedications = medications
        let originalDoses = doses

        medications = medications.filter { $0.id != id }
        doses.removeAll { $0.medicationId == id }

        Task { @MainActor in
            do {
                try await service.deleteMedication(id: id)
            } catch {
                print("[MedicationStore] delete failed: \(error)")
                medications = originalMedications
                doses = originalDoses
            }
        }
    }

    var takenCount: Int { doses.filter(\.isDone).count }
    var totalCount: Int { doses.count }
    var progress: Double {
        totalCount > 0 ? Double(takenCount) / Double(totalCount) : 0
    }
}

// MARK: - Dose Entry
struct DoseEntry: Identifiable {
    let id = UUID()
    let medicationId: String
    let time: String
    let name: String
    var isDone: Bool
}

// MARK: - Medication Confirmation
struct MedicationConfirmation: Identifiable, Codable {
    let id: String
    let medication: String
    let scheduledTime: String
    let confirmedAt: Date
    let photoUrl: String?
    let note: String?
    /// API: note_translated — 照護者填的確認 note 多語版本。
    var noteTranslations: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case id, medication, scheduledTime, confirmedAt, photoUrl, note
        case noteTranslated
    }

    init(id: String, medication: String, scheduledTime: String, confirmedAt: Date,
         photoUrl: String?, note: String?, noteTranslations: [String: String]? = nil) {
        self.id = id; self.medication = medication; self.scheduledTime = scheduledTime
        self.confirmedAt = confirmedAt; self.photoUrl = photoUrl; self.note = note
        self.noteTranslations = noteTranslations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        medication = (try? c.decodeIfPresent(String.self, forKey: .medication)) ?? ""
        scheduledTime = (try? c.decodeIfPresent(String.self, forKey: .scheduledTime)) ?? ""
        confirmedAt = (try? c.decodeIfPresent(Date.self, forKey: .confirmedAt)) ?? Date()
        photoUrl = try? c.decodeIfPresent(String.self, forKey: .photoUrl)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        noteTranslations = try? c.decodeIfPresent([String: String].self, forKey: .noteTranslated)
    }

    func displayNote(language: String?) -> String? {
        guard let note else { return nil }
        return translatedText(original: note, translations: noteTranslations, language: language)
    }

    // Encode only the fields we ever send back (currently never — confirmations
    // are server-created), but Codable conformance needs an explicit encode
    // because we declared CodingKeys with decode-only keys (noteTranslated).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(medication, forKey: .medication)
        try c.encode(scheduledTime, forKey: .scheduledTime)
        try c.encode(confirmedAt, forKey: .confirmedAt)
        try c.encodeIfPresent(photoUrl, forKey: .photoUrl)
        try c.encodeIfPresent(note, forKey: .note)
    }
}

struct ConfirmMedicationRequest: Codable {
    let scheduledTime: String
    let photoUrl: String?
    let note: String?
}

// MARK: - Medication
struct Medication: Identifiable, Codable {
    var id: String
    var name: String
    var nameTranslated: String       // API: name_translated (dict in backend; Swift keeps first value)
    var dosage: String
    var frequency: String            // "daily" / "twice_daily" / "weekly" / "as_needed"
    var times: [String]
    var instructions: String         // API: instructions (was previously `notes`)
    /// API: instructions_translated — 注意事項是自由文字，要翻譯。藥品名稱
    /// 屬於 medical entity，依 handoff 規範刻意保留原文不翻。
    var instructionsTranslations: [String: String]?
    var isActive: Bool               // API: is_active
    var startDate: Date              // API: start_date (yyyy-MM-dd)
    var endDate: Date?               // API: end_date
    var reminderEnabled: Bool        // API: reminder_enabled

    private enum CodingKeys: String, CodingKey {
        // All snake_case keys auto-converted by .convertFromSnakeCase
        case id, name, dosage, frequency, times, instructions
        case nameTranslated, instructionsTranslated
        case isActive, startDate, endDate, reminderEnabled
    }

    init(id: String = UUID().uuidString, name: String, nameTranslated: String,
         dosage: String, frequency: String, times: [String], instructions: String,
         isActive: Bool = true, startDate: Date = Date(), endDate: Date? = nil,
         reminderEnabled: Bool = true,
         instructionsTranslations: [String: String]? = nil) {
        self.id = id; self.name = name; self.nameTranslated = nameTranslated
        self.dosage = dosage; self.frequency = frequency; self.times = times
        self.instructions = instructions; self.isActive = isActive
        self.startDate = startDate; self.endDate = endDate; self.reminderEnabled = reminderEnabled
        self.instructionsTranslations = instructionsTranslations
    }

    func displayInstructions(language: String?) -> String {
        translatedText(original: instructions, translations: instructionsTranslations, language: language)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(String.self, forKey: .id)
        name           = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        dosage         = (try? c.decodeIfPresent(String.self, forKey: .dosage)) ?? ""
        frequency      = (try? c.decodeIfPresent(String.self, forKey: .frequency)) ?? "daily"
        times          = (try? c.decodeIfPresent([String].self, forKey: .times)) ?? []
        instructions   = (try? c.decodeIfPresent(String.self, forKey: .instructions)) ?? ""
        instructionsTranslations = try? c.decodeIfPresent([String: String].self, forKey: .instructionsTranslated)
        isActive       = (try? c.decodeIfPresent(Bool.self, forKey: .isActive)) ?? true
        reminderEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .reminderEnabled)) ?? true
        // name_translated is JSONB {lang: text} on backend — pick first non-empty value
        if let dict = try? c.decodeIfPresent([String: String].self, forKey: .nameTranslated) {
            nameTranslated = dict.values.first(where: { !$0.isEmpty }) ?? name
        } else {
            nameTranslated = (try? c.decodeIfPresent(String.self, forKey: .nameTranslated)) ?? name
        }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        if let s = try? c.decodeIfPresent(String.self, forKey: .startDate),
           let d = df.date(from: s) {
            startDate = d
        } else {
            startDate = Date()
        }
        if let s = try? c.decodeIfPresent(String.self, forKey: .endDate),
           let d = df.date(from: s) {
            endDate = d
        } else {
            endDate = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        // Matches backend CreateMedicationSerializer: name, dosage, frequency, times,
        // instructions, start_date, end_date, reminder_enabled.
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(dosage, forKey: .dosage)
        try c.encode(frequency, forKey: .frequency)
        try c.encode(times, forKey: .times)
        try c.encode(instructions, forKey: .instructions)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        try c.encode(df.string(from: startDate), forKey: .startDate)
        try c.encodeIfPresent(endDate.map { df.string(from: $0) }, forKey: .endDate)
        try c.encode(reminderEnabled, forKey: .reminderEnabled)
    }

    static var samples: [Medication] {
        [
            Medication(name: "Amlodipine", nameTranslated: "氨氯地平",
                       dosage: "5mg", frequency: "daily", times: ["08:00"],
                       instructions: "飯後服用，注意低血壓"),
            Medication(name: "Metformin", nameTranslated: "二甲雙胍",
                       dosage: "500mg", frequency: "twice_daily", times: ["08:00", "18:00"],
                       instructions: "飯中服用"),
            Medication(name: "Aspirin", nameTranslated: "阿斯匹靈",
                       dosage: "100mg", frequency: "daily", times: ["08:00"],
                       instructions: "飯後服用，勿空腹"),
        ]
    }
}

// MARK: - Expense
struct Expense: Identifiable, Codable {
    var id: String
    var title: String
    var amount: Double
    var category: String
    var date: Date
    var hasReceipt: Bool
    /// 收據圖片下載 URL（後端回傳時為 presigned GET URL，POST 時帶入上傳後的 bare URL）
    var imageUrl: String?
    var rawImageKey: String?
    var deidStatus: String?
    /// 去背後的發票圖片，僅存在記憶體中（不序列化至 JSON/API）
    var receiptImage: UIImage? = nil

    enum CodingKeys: String, CodingKey {
        case id, date, items, imageUrl, rawImageKey, deidStatus, hasImage
        case title = "storeName"       // API: store_name → convertFromSnakeCase → storeName
        case amount = "totalAmount"    // API: total_amount → totalAmount
        // `category` is UI-only — backend stores category per item inside `items` JSONB.
    }

    init(id: String, title: String, amount: Double, category: String, date: Date,
         hasReceipt: Bool, imageUrl: String? = nil, rawImageKey: String? = nil,
         deidStatus: String? = nil, receiptImage: UIImage? = nil) {
        self.id = id; self.title = title; self.amount = amount
        self.category = category; self.date = date; self.hasReceipt = hasReceipt
        self.imageUrl = imageUrl
        self.rawImageKey = rawImageKey
        self.deidStatus = deidStatus
        self.receiptImage = receiptImage
    }

    /// 五個正規分類 wire code —— UI 顯示名稱透過 `localizedDisplayName`
    /// 翻譯，所以 picker、summary、breakdown 全部都帶 code，不再夾帶
    /// 中文字串。zhTW/vi/id/tl 對應放在 Localizable.xcstrings。
    static let allCategoryCodes: [String] = ["medical", "food", "daily", "transport", "other"]

    static func localizedCategoryKey(_ code: String) -> LocalizedStringKey {
        switch code {
        case "medical":   return "category.medical"
        case "food":      return "category.food"
        case "daily":     return "category.daily"
        case "transport": return "category.transport"
        case "other":     return "category.other"
        default:          return LocalizedStringKey(code)
        }
    }

    /// 純 String 用途（CSV 匯出、無法吃 LocalizedStringKey 的 Text）。
    static func localizedCategoryName(_ code: String, locale: Locale = .current) -> String {
        let key = "category.\(code)"
        let bundle = Bundle.main
        let value = bundle.localizedString(forKey: key, value: code, table: nil)
        return value
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(String.self, forKey: .id)
        title    = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        // Backend stores per-item category as enum keys inside `items` JSONB
        // (medical / food / daily / transport / other). 直接收 wire code，
        // 顯示時才透過 localizedCategoryKey 轉成當前語言。
        if let items = try? c.decodeIfPresent([[String: String]].self, forKey: .items),
           let raw = items.first?["category"], !raw.isEmpty {
            category = raw
        } else {
            category = ""
        }
        // total_amount may arrive as String ("339.00") or Number
        if let s = try? c.decode(String.self, forKey: .amount) {
            amount = Double(s) ?? 0
        } else {
            amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        }
        // date is "yyyy-MM-dd"
        let dateStr = try c.decode(String.self, forKey: .date)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        date = df.date(from: dateStr) ?? Date()
        // Backend 在 list 不再回傳 presigned image_url（每筆都簽一次太貴），
        // 改用 has_image 旗標判斷有沒有發票；presigned URL 等到 retrieve 才拿。
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        rawImageKey = try c.decodeIfPresent(String.self, forKey: .rawImageKey)
        deidStatus = try c.decodeIfPresent(String.self, forKey: .deidStatus)
        let hasImage = try c.decodeIfPresent(Bool.self, forKey: .hasImage) ?? false
        hasReceipt = (hasImage || imageUrl != nil || rawImageKey != nil || deidStatus == "processing")
    }

    func encode(to encoder: Encoder) throws {
        // Matches backend CreateExpenseSerializer: store_name, date, items, total_amount, raw_image_key.
        // Category is embedded inside `items` per backend schema.
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title,  forKey: .title)
        try c.encode(amount, forKey: .amount)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        try c.encode(df.string(from: date), forKey: .date)
        // category 已經是 wire code（medical / food / daily / transport / other），
        // 直接帶出去；舊資料若仍是中文，留原樣讓後端驗證再拋錯比較好抓到。
        let item: [String: String] = [
            "name": title,
            "category": category,
        ]
        try c.encode([item], forKey: .items)
        if let rawImageKey {
            try c.encode(rawImageKey, forKey: .rawImageKey)
        }
    }

    var categoryIcon: String {
        switch category {
        case "medical":   return "cross.fill"
        case "food":      return "fork.knife"
        case "daily":     return "shippingbox.fill"
        case "transport": return "car.fill"
        case "other":     return "bag.fill"
        default:          return "bag.fill"
        }
    }

    var categoryColor: Color {
        switch category {
        case "medical":   return Color(red: 0.0, green: 0.55, blue: 0.6)
        case "food":      return .orange
        case "daily":     return .purple
        case "transport": return .blue
        case "other":     return .pink
        default:          return .gray
        }
    }

    /// SwiftUI `Text` 用：吃 LocalizedStringKey，會走 Localizable.xcstrings。
    var categoryDisplayKey: LocalizedStringKey { Expense.localizedCategoryKey(category) }
    /// Backward-compat：CSV / 純字串拼接才用，不再回傳 wire code。
    var categoryDisplayName: String { Expense.localizedCategoryName(category) }

    static var samples: [Expense] {
        [
            Expense(id: UUID().uuidString, title: "健檢費用 - 慈濟醫院", amount: 12000, category: "醫療保健",
                    date: Date().addingTimeInterval(-3600 * 3), hasReceipt: true),
            Expense(id: UUID().uuidString, title: "全聯福利中心 - 食品", amount: 1450, category: "日常飲食",
                    date: Date().addingTimeInterval(-3600 * 6), hasReceipt: true),
            Expense(id: UUID().uuidString, title: "成人紙尿褲 - 屈臣氏", amount: 3200, category: "生活用品",
                    date: Date().addingTimeInterval(-86400), hasReceipt: true),
            Expense(id: UUID().uuidString, title: "處方藥費 - 杏一藥局", amount: 850, category: "醫療保健",
                    date: Date().addingTimeInterval(-86400 * 2), hasReceipt: true),
        ]
    }

    static var monthlyTotal: Double { 24850 }

    /// Fallback breakdown 用 wire codes，跟 backend `categoryBreakdown[].category`
    /// 對齊；UI 拿去 `Expense.localizedCategoryKey` 轉成顯示字。
    static var categoryBreakdown: [(String, Double, Color)] {
        [
            ("medical", 45, Color(red: 0.0, green: 0.55, blue: 0.6)),
            ("food",    25, .orange),
            ("daily",   20, .purple),
            ("other",   10, .gray),
        ]
    }
}

// MARK: - Todo
enum Priority: String, CaseIterable, Codable {
    case high   = "high"
    case medium = "medium"
    case low    = "low"

    var displayName: String {
        switch self {
        case .high:   return String(localized: "高")
        case .medium: return String(localized: "中")
        case .low:    return String(localized: "低")
        }
    }

    var color: Color {
        switch self {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .green
        }
    }
}

struct TodoItem: Identifiable, Codable {
    var id: String
    var title: String
    /// API: `title_translated` — { "zh-TW": "...", "vi": "...", ... }
    /// 後端會把建立者填的 title 翻成所有支援語言。UI 透過
    /// `displayTitle(language:)` 取對應翻譯，缺則回原文。
    var titleTranslations: [String: String]?
    var assignee: String    // API: assignee.name (read-only display)
    var assigneeId: String? // API: assignee.id — required by CreateTodoSerializer as `assignee_id`
    var priority: Priority
    var dueDate: Date?      // API: due_date (date-only string)
    var isCompleted: Bool   // API: status == "completed"

    private enum CodingKeys: String, CodingKey {
        // All snake_case keys auto-converted by .convertFromSnakeCase
        case id, title, priority, assignee, status
        case dueDate, assigneeId, titleTranslated
    }
    private enum AssigneeKeys: String, CodingKey { case id, name }

    init(id: String, title: String, assignee: String, priority: Priority,
         dueDate: Date?, isCompleted: Bool, assigneeId: String? = nil,
         titleTranslations: [String: String]? = nil) {
        self.id = id; self.title = title; self.assignee = assignee
        self.assigneeId = assigneeId
        self.priority = priority; self.dueDate = dueDate; self.isCompleted = isCompleted
        self.titleTranslations = titleTranslations
    }

    func displayTitle(language: String?) -> String {
        translatedText(original: title, translations: titleTranslations, language: language)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(String.self, forKey: .id)
        title    = try c.decode(String.self, forKey: .title)
        titleTranslations = try c.decodeIfPresent([String: String].self, forKey: .titleTranslated)
        priority = try c.decode(Priority.self, forKey: .priority)
        if let dateStr = try? c.decodeIfPresent(String.self, forKey: .dueDate) {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            dueDate = fmt.date(from: dateStr ?? "")
        } else {
            dueDate = nil
        }
        let status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        isCompleted = (status == "completed")
        if let ac = try? c.nestedContainer(keyedBy: AssigneeKeys.self, forKey: .assignee) {
            assignee   = (try? ac.decode(String.self, forKey: .name)) ?? ""
            assigneeId = try? ac.decode(String.self, forKey: .id)
        } else {
            assignee   = (try? c.decode(String.self, forKey: .assignee)) ?? ""
            assigneeId = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        // Matches backend CreateTodoSerializer: title, assignee_id (UUID), priority, due_date.
        // For PUT updates, also include status.
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(priority, forKey: .priority)
        try c.encodeIfPresent(assigneeId, forKey: .assigneeId)
        if let dueDate {
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            try c.encode(fmt.string(from: dueDate), forKey: .dueDate)
        }
        try c.encode(isCompleted ? "completed" : "pending", forKey: .status)
    }

    static var samples: [TodoItem] {
        [
            TodoItem(id: UUID().uuidString, title: "安排回診掛號（台大醫院心臟科）",
                     assignee: "林小明", priority: .high,
                     dueDate: Date().addingTimeInterval(86400 * 3), isCompleted: false),
            TodoItem(id: UUID().uuidString, title: "補購復健護具",
                     assignee: "Rita Santos", priority: .medium,
                     dueDate: Date().addingTimeInterval(86400), isCompleted: false),
            TodoItem(id: UUID().uuidString, title: "更新健保卡資料",
                     assignee: "林大華", priority: .low,
                     dueDate: nil, isCompleted: true),
        ]
    }
}

// MARK: - Calendar Event
struct CalendarEvent: Identifiable, Codable {
    var id: String
    var title: String
    /// API: title_translated — UI 透過 displayTitle(language:) 取對應翻譯。
    var titleTranslations: [String: String]?
    var note: String?
    var noteTranslations: [String: String]?
    var date: Date      // API: start_time
    var location: String?
    var type: String    // API types: "medical" / "medication" / "rehab" / "leave" / "personal" / "other"

    private enum CodingKeys: String, CodingKey {
        case id, title, location, type, note
        case date = "startTime"   // API: start_time → convertFromSnakeCase → startTime
        case titleTranslated, noteTranslated
    }

    init(id: String, title: String, date: Date, location: String?, type: String,
         note: String? = nil,
         titleTranslations: [String: String]? = nil,
         noteTranslations: [String: String]? = nil) {
        self.id = id; self.title = title; self.date = date
        self.location = location; self.type = type
        self.note = note
        self.titleTranslations = titleTranslations
        self.noteTranslations = noteTranslations
    }

    func displayTitle(language: String?) -> String {
        translatedText(original: title, translations: titleTranslations, language: language)
    }

    func displayNote(language: String?) -> String? {
        guard let note else { return nil }
        return translatedText(original: note, translations: noteTranslations, language: language)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(String.self, forKey: .id)
        title    = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        titleTranslations = try? c.decodeIfPresent([String: String].self, forKey: .titleTranslated)
        note     = try? c.decodeIfPresent(String.self, forKey: .note)
        noteTranslations = try? c.decodeIfPresent([String: String].self, forKey: .noteTranslated)
        date     = (try? c.decodeIfPresent(Date.self, forKey: .date)) ?? Date()
        location = try? c.decodeIfPresent(String.self, forKey: .location)
        type     = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "other"
    }

    func encode(to encoder: Encoder) throws {
        // Matches backend CreateEventSerializer: title, start_time, end_time,
        // location, type, reminder_minutes, note. Server assigns id/family/created_by.
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(date, forKey: .date)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encode(backendType, forKey: .type)
    }

    /// Maps the display type (Chinese) to a backend Event.Type enum value.
    var backendType: String {
        switch type {
        case "回診", "medical":      return "medical"
        case "用藥", "medication":   return "medication"
        case "復健", "rehab":        return "rehab"
        case "請假", "leave":        return "leave"
        case "個人", "personal":     return "personal"
        default:                     return "other"
        }
    }

    var typeIcon: String {
        switch type {
        case "回診", "medical":      return "stethoscope"
        case "復健", "rehab":        return "figure.walk"
        case "用藥", "medication":   return "pills.fill"
        case "完成":                 return "checkmark.circle.fill"
        case "待辦":                 return "checklist"
        case "leave":               return "calendar.badge.exclamationmark"
        case "personal":            return "person.fill"
        default:                    return "calendar"
        }
    }

    var typeColor: Color {
        switch type {
        case "回診", "medical":      return Color(red: 0.0, green: 0.55, blue: 0.6)
        case "復健", "rehab":        return .green
        case "用藥", "medication":   return .blue
        case "完成":                 return .orange
        case "待辦":                 return .purple
        case "leave":               return .orange
        case "personal":            return .gray
        default:                    return .gray
        }
    }

    static var samples: [CalendarEvent] {
        [
            CalendarEvent(id: UUID().uuidString, title: "心臟科回診", date: Date().addingTimeInterval(86400 * 5),
                          location: "台大醫院心臟科門診", type: "回診"),
            CalendarEvent(id: UUID().uuidString, title: "物理治療復健", date: Date().addingTimeInterval(86400 * 2),
                          location: "復健科", type: "復健"),
            CalendarEvent(id: UUID().uuidString, title: "服藥提醒", date: Date().addingTimeInterval(3600 * 2),
                          location: nil, type: "用藥"),
        ]
    }
}

// MARK: - Leave Request
enum LeaveStatus: String, Codable {
    case pending  = "pending"
    case approved = "approved"
    case rejected = "rejected"
    case withdrawn = "withdrawn"

    var displayName: String {
        switch self {
        case .pending:  return String(localized: "待審核")
        case .approved: return String(localized: "已核准")
        case .rejected: return String(localized: "已拒絕")
        case .withdrawn: return String(localized: "已撤回")
        }
    }

    var color: Color {
        switch self {
        case .pending:  return .orange
        case .approved: return .green
        case .rejected: return .red
        case .withdrawn: return .gray
        }
    }
}

/// 家屬對請假申請的投票
struct LeaveVote: Identifiable, Codable {
    var id: String
    var memberId: String
    var memberName: String
    var isAvailable: Bool       // true = 有空（同意）, false = 沒空（不同意）
    var votedAt: Date?
}

struct LeaveRequest: Identifiable, Codable {
    var id: String
    var type: String        // API: "personal" / "sick" / "emergency"
    var startDate: Date     // API: start_date (date-only)
    var endDate: Date       // API: end_date (date-only)
    var reason: String
    var status: LeaveStatus
    var applicantName: String?  // 申請人姓名
    var votes: [LeaveVote]?     // 家屬投票
    /// API: reason_translations — 多語言版本的 reason。
    var reasonTranslated: String?
    var reasonTranslations: [String: String]?

    private enum CodingKeys: String, CodingKey {
        // All snake_case keys auto-converted by .convertFromSnakeCase
        case id, type, reason, status, startDate, endDate, applicantName, votes
        case reasonTranslated, reasonTranslations
    }

    init(id: String, type: String, startDate: Date, endDate: Date,
         reason: String, status: LeaveStatus,
         applicantName: String? = nil, votes: [LeaveVote]? = nil,
         reasonTranslated: String? = nil,
         reasonTranslations: [String: String]? = nil) {
        self.id = id; self.type = type; self.startDate = startDate
        self.endDate = endDate; self.reason = reason; self.status = status
        self.applicantName = applicantName; self.votes = votes
        self.reasonTranslated = reasonTranslated
        self.reasonTranslations = reasonTranslations
    }

    func displayReason(language: String?) -> String {
        translatedText(
            original: reasonTranslated ?? reason,
            translations: reasonTranslations,
            language: language
        )
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id     = try c.decode(String.self, forKey: .id)
        type   = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "personal"
        reason = (try? c.decodeIfPresent(String.self, forKey: .reason)) ?? ""
        reasonTranslated = try? c.decodeIfPresent(String.self, forKey: .reasonTranslated)
        reasonTranslations = try? c.decodeIfPresent([String: String].self, forKey: .reasonTranslations)
        status = (try? c.decodeIfPresent(LeaveStatus.self, forKey: .status)) ?? .pending
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let s1 = (try? c.decodeIfPresent(String.self, forKey: .startDate)) ?? ""
        let s2 = (try? c.decodeIfPresent(String.self, forKey: .endDate)) ?? ""
        startDate = fmt.date(from: s1) ?? Date()
        endDate   = fmt.date(from: s2) ?? startDate
        applicantName = try? c.decodeIfPresent(String.self, forKey: .applicantName)
        votes = try? c.decodeIfPresent([LeaveVote].self, forKey: .votes)
    }

    func encode(to encoder: Encoder) throws {
        // Matches backend CreateLeaveSerializer: type, start_date, end_date, reason.
        // Server assigns id/status/days/applicant/family.
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(backendType, forKey: .type)
        try c.encode(reason, forKey: .reason)
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        try c.encode(fmt.string(from: startDate), forKey: .startDate)
        try c.encode(fmt.string(from: endDate), forKey: .endDate)
    }

    var typeDisplayName: String {
        switch type {
        case "personal", "事假": return String(localized: "事假")
        case "sick",     "病假": return String(localized: "病假")
        case "emergency","緊急": return String(localized: "緊急假")
        default: return type
        }
    }

    /// Maps display type (Chinese or English) to backend Leave.Type enum value.
    var backendType: String {
        switch type {
        case "事假", "personal":  return "personal"
        case "病假", "sick":      return "sick"
        case "緊急", "急事", "emergency": return "emergency"
        default: return "personal"
        }
    }

    static var samples: [LeaveRequest] {
        [
            LeaveRequest(id: UUID().uuidString, type: "personal",
                         startDate: Date().addingTimeInterval(86400 * 10),
                         endDate: Date().addingTimeInterval(86400 * 12),
                         reason: "返鄉探親", status: .pending),
            LeaveRequest(id: UUID().uuidString, type: "sick",
                         startDate: Date().addingTimeInterval(-86400 * 7),
                         endDate: Date().addingTimeInterval(-86400 * 6),
                         reason: "就醫", status: .approved),
        ]
    }
}

// MARK: - Document
struct AppDocument: Identifiable, Codable {
    var id: String
    var title: String
    var category: String    // API: "insurance" / "medical" / "id_document" / "contract" / "other"
    var fileSize: String    // derived from API file_size (Int bytes)
    var uploadDate: Date    // API: created_at
    var localURL: URL?      // 本地暫存路徑，供 QuickLook 預覽用（非 API 欄位）
    var remoteURL: URL?
    var deidStatus: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, category, deidStatus
        case remoteURL = "fileUrl"
        case fileSizeBytes = "fileSize"    // API: file_size → convertFromSnakeCase → fileSize
        case uploadDate    = "createdAt"   // API: created_at → createdAt
    }

    init(id: String, title: String, category: String, fileSize: String, uploadDate: Date, localURL: URL? = nil, remoteURL: URL? = nil, deidStatus: String? = nil) {
        self.id = id; self.title = title; self.category = category
        self.fileSize = fileSize; self.uploadDate = uploadDate; self.localURL = localURL
        self.remoteURL = remoteURL
        self.deidStatus = deidStatus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(String.self, forKey: .id)
        title      = try c.decode(String.self, forKey: .title)
        category   = try c.decode(String.self, forKey: .category)
        deidStatus = try c.decodeIfPresent(String.self, forKey: .deidStatus)
        uploadDate = try c.decode(Date.self, forKey: .uploadDate)
        localURL   = nil
        remoteURL  = try c.decodeIfPresent(URL.self, forKey: .remoteURL)
        let bytes  = (try? c.decodeIfPresent(Int.self, forKey: .fileSizeBytes)) ?? 0
        let mb     = Double(bytes) / 1_048_576
        fileSize   = mb >= 1 ? String(format: "%.1f MB", mb) : String(format: "%.0f KB", Double(bytes) / 1024)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(category, forKey: .category)
    }

    var normalizedDeidStatus: String {
        deidStatus ?? "completed"
    }

    var isAwaitingDeidentification: Bool {
        normalizedDeidStatus == "pending" || normalizedDeidStatus == "processing"
    }

    var hasFailedDeidentification: Bool {
        normalizedDeidStatus == "failed"
    }

    var previewURL: URL? {
        guard !isAwaitingDeidentification, !hasFailedDeidentification else { return nil }
        return remoteURL
    }

    var categoryIcon: String {
        switch category {
        case "insurance", "保險": return "shield.fill"
        case "medical", "醫療":   return "cross.fill"
        case "id_document", "證件": return "creditcard.fill"
        case "contract", "合約":  return "doc.text.fill"
        default: return "folder.fill"
        }
    }

    var categoryColor: Color {
        switch category {
        case "insurance", "保險": return .blue
        case "medical", "醫療":   return .red
        case "id_document", "證件": return .orange
        case "contract", "合約":  return .purple
        default: return .gray
        }
    }

    var categoryDisplayName: String {
        switch category {
        case "insurance":  return String(localized: "保險")
        case "medical":    return String(localized: "醫療")
        case "id_document": return String(localized: "證件")
        case "contract":   return String(localized: "合約")
        case "other":      return String(localized: "其他")
        default:           return category
        }
    }

    static var samples: [AppDocument] {
        [
            AppDocument(id: UUID().uuidString, title: "長照保險單2024", category: "保險",
                        fileSize: "2.3 MB", uploadDate: Date().addingTimeInterval(-86400 * 30)),
            AppDocument(id: UUID().uuidString, title: "最新健康檢查報告", category: "醫療",
                        fileSize: "5.1 MB", uploadDate: Date().addingTimeInterval(-86400 * 14)),
            AppDocument(id: UUID().uuidString, title: "身份證正反面", category: "證件",
                        fileSize: "0.8 MB", uploadDate: Date().addingTimeInterval(-86400 * 60)),
        ]
    }
}

// MARK: - Notification
enum NotificationCategory: String, Codable {
    case health              = "health_alert"
    case medication          = "medication_reminder"
    case medicationConfirmed = "medication_confirmed"
    case leave               = "leave_request"
    case leaveStatus         = "leave_status"
    case leaveApproved       = "leave_approved"
    case leaveRejected       = "leave_rejected"
    case purchase            = "board_request"
    case purchaseApproved    = "board_approved"
    case expenseScanned      = "expense_scanned"
    case sos                 = "sos"
    case sosTriggered        = "sos_triggered"
    case sosResolved         = "sos_resolved"
    case eventReminder       = "event_reminder"
    case todo                = "todo_assigned"
    case chat                = "chat_message"

    var icon: String {
        switch self {
        case .health: return "heart.fill"
        case .medication, .medicationConfirmed: return "pills.fill"
        case .leave, .leaveStatus, .leaveApproved, .leaveRejected: return "calendar.badge.exclamationmark"
        case .chat: return "message.fill"
        case .sos, .sosTriggered, .sosResolved: return "sos"
        case .todo: return "checkmark.circle.fill"
        case .purchase, .purchaseApproved: return "cart.fill"
        case .expenseScanned: return "doc.text.viewfinder"
        case .eventReminder: return "calendar"
        }
    }

    var color: Color {
        switch self {
        case .health: return .red
        case .medication, .medicationConfirmed: return Color(red: 0.0, green: 0.55, blue: 0.6)
        case .leave, .leaveStatus: return .orange
        case .leaveApproved: return .green
        case .leaveRejected: return .red
        case .chat: return .green
        case .sos, .sosTriggered, .sosResolved: return .red
        case .todo: return .purple
        case .purchase, .purchaseApproved: return .blue
        case .expenseScanned: return .teal
        case .eventReminder: return .orange
        }
    }
}

struct AppNotification: Identifiable, Codable {
    var id: String
    var category: NotificationCategory
    var title: String
    var body: String
    var timestamp: Date
    var isRead: Bool
    /// API: title_translated / body_translated — dict 形式的多語版本，
    /// 推播時後端會挑當前 user.language 推；但歷史通知列表可能跨語言混雜，
    /// 所以 UI 仍依 LocaleStore 選對應翻譯。
    var titleTranslations: [String: String]?
    var bodyTranslations: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, title, body
        case category = "type"    // API: "type" field → renamed to category in Swift
        case isRead               // API: is_read → convertFromSnakeCase → isRead
        case timestamp = "createdAt"  // API: created_at → createdAt
        case titleTranslated, bodyTranslated
    }

    init(id: String, category: NotificationCategory, title: String, body: String,
         timestamp: Date, isRead: Bool,
         titleTranslations: [String: String]? = nil,
         bodyTranslations: [String: String]? = nil) {
        self.id = id; self.category = category; self.title = title; self.body = body
        self.timestamp = timestamp; self.isRead = isRead
        self.titleTranslations = titleTranslations
        self.bodyTranslations = bodyTranslations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(String.self, forKey: .id)
        category  = (try? c.decodeIfPresent(NotificationCategory.self, forKey: .category)) ?? .chat
        title     = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        body      = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        timestamp = (try? c.decodeIfPresent(Date.self, forKey: .timestamp)) ?? Date()
        isRead    = (try? c.decodeIfPresent(Bool.self, forKey: .isRead)) ?? false
        titleTranslations = try? c.decodeIfPresent([String: String].self, forKey: .titleTranslated)
        bodyTranslations  = try? c.decodeIfPresent([String: String].self, forKey: .bodyTranslated)
    }

    func displayTitle(language: String?) -> String {
        let resolved = translatedText(original: title, translations: titleTranslations, language: language)
        guard resolved == title else { return resolved }
        guard language == "vi" else { return resolved }

        if category == .chat {
            if let sender = title.strippingKnownPrefix("New message from ") {
                return "Tin nhắn mới từ \(sender)"
            }
            if let sender = title.strippingKnownPrefix("新訊息來自 ") {
                return "Tin nhắn mới từ \(sender)"
            }
            if let sender = title.strippingKnownSuffix(" 的新訊息") {
                return "Tin nhắn mới từ \(sender)"
            }
        }

        return resolved
    }

    func displayBody(language: String?) -> String {
        translatedText(original: body, translations: bodyTranslations, language: language)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(category, forKey: .category)
        try c.encode(title, forKey: .title)
        try c.encode(body, forKey: .body)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(isRead, forKey: .isRead)
    }

    static var samples: [AppNotification] {
        [
            AppNotification(id: UUID().uuidString, category: .health, title: "心率異常警示",
                            body: "爸爸心率達到 112 bpm，超出正常範圍",
                            timestamp: Date().addingTimeInterval(-1800), isRead: false),
            AppNotification(id: UUID().uuidString, category: .medication, title: "用藥提醒",
                            body: "下午 2:00 Metformin 500mg 服藥時間到",
                            timestamp: Date().addingTimeInterval(-3600), isRead: false),
            AppNotification(id: UUID().uuidString, category: .leave, title: "請假申請",
                            body: "Rita Santos 申請 4/20-4/22 事假，請審核",
                            timestamp: Date().addingTimeInterval(-7200), isRead: true),
            AppNotification(id: UUID().uuidString, category: .purchase, title: "採購需求",
                            body: "Rita Santos 申請補購成人尿布 x 2 包",
                            timestamp: Date().addingTimeInterval(-10800), isRead: true),
        ]
    }
}

// MARK: - Message Board (Purchase Requests)
// Backend (`board_requests`) stores: category, items (JSONB list), note, status, requester(User).
// The UI surfaces a title/description from the items list and requester name.
struct PurchaseRequest: Identifiable, Codable {
    var id: String
    var title: String           // derived from items[0].name
    var category: String        // API: category
    var description: String     // derived from items (name × quantity, joined)
    var estimatedCost: Double?  // local-only (backend has no cost field)
    var status: String          // API: status (pending / approved / rejected / completed)
    var createdAt: Date         // API: created_at
    var requester: String       // API: requester.name
    var notes: String           // API: note
    var noteTranslated: String?   // API: note_translated
    var noteTranslations: [String: String]?  // API: note_translations
    var reply: String?           // API: reply（家屬回覆）
    var replyTranslations: [String: String]?  // API: reply_translations
    var items: [PurchaseItem]   // API: items JSONB

    struct PurchaseItem: Codable, Hashable {
        var name: String
        /// API: items[].name_translated — 後端是 dict { lang: text }；舊欄位
        /// 也曾經是 String，做向下相容 decode。
        var nameTranslations: [String: String]?
        var quantity: String?

        enum CodingKeys: String, CodingKey {
            case name, quantity, nameTranslated
        }

        init(name: String, nameTranslations: [String: String]? = nil, quantity: String? = nil) {
            self.name = name; self.nameTranslations = nameTranslations; self.quantity = quantity
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name     = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
            quantity = try? c.decodeIfPresent(String.self, forKey: .quantity)
            if let dict = try? c.decodeIfPresent([String: String].self, forKey: .nameTranslated) {
                nameTranslations = dict
            } else if let single = try? c.decodeIfPresent(String.self, forKey: .nameTranslated),
                      !single.isEmpty {
                nameTranslations = ["zh-TW": single]
            } else {
                nameTranslations = nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encodeIfPresent(quantity, forKey: .quantity)
        }

        func displayName(language: String?) -> String {
            translatedText(original: name, translations: nameTranslations, language: language)
        }
    }

    private enum CodingKeys: String, CodingKey {
        // created_at → convertFromSnakeCase → createdAt
        case id, category, status, items, requester, createdAt, note
        case noteTranslated, noteTranslations, reply, replyTranslations
    }
    private enum RequesterKeys: String, CodingKey { case name }

    init(id: String, title: String, category: String, description: String,
         estimatedCost: Double?, status: String, createdAt: Date,
         requester: String, notes: String, items: [PurchaseItem] = [],
         noteTranslated: String? = nil,
         noteTranslations: [String: String]? = nil,
         reply: String? = nil,
         replyTranslations: [String: String]? = nil) {
        self.id = id; self.title = title; self.category = category
        self.description = description; self.estimatedCost = estimatedCost
        self.status = status; self.createdAt = createdAt
        self.requester = requester; self.notes = notes; self.items = items
        self.noteTranslated = noteTranslated
        self.noteTranslations = noteTranslations
        self.reply = reply
        self.replyTranslations = replyTranslations
    }

    func displayNotes(language: String?) -> String {
        translatedText(
            original: noteTranslated ?? notes,
            translations: noteTranslations,
            language: language
        )
    }

    func displayReply(language: String?) -> String? {
        guard let reply else { return nil }
        return translatedText(original: reply, translations: replyTranslations, language: language)
    }

    func displayTitle(language: String?) -> String {
        items.first?.displayName(language: language) ?? title
    }

    func displayDescription(language: String?) -> String {
        items
            .map { [$0.displayName(language: language), $0.quantity].compactMap { $0 }.joined(separator: " × ") }
            .joined(separator: "，")
    }

    // Backend only accepts enum keys: food | daily | medical | other.
    // UI uses Chinese labels; map both ways so the wire format stays valid.
    private static let categoryToWire: [String: String] = [
        "食品": "food", "日用品": "daily", "醫療用品": "medical", "其他": "other",
    ]
    private static let wireToCategory: [String: String] = [
        "food": "食品", "daily": "日用品", "medical": "醫療用品", "other": "其他",
    ]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(String.self, forKey: .id)
        let rawCat = (try? c.decodeIfPresent(String.self, forKey: .category)) ?? ""
        category  = PurchaseRequest.wireToCategory[rawCat] ?? rawCat
        status    = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "pending"
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        notes     = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        noteTranslated = try? c.decodeIfPresent(String.self, forKey: .noteTranslated)
        noteTranslations = try? c.decodeIfPresent([String: String].self, forKey: .noteTranslations)
        reply     = try? c.decodeIfPresent(String.self, forKey: .reply)
        replyTranslations = try? c.decodeIfPresent([String: String].self, forKey: .replyTranslations)
        items     = (try? c.decodeIfPresent([PurchaseItem].self, forKey: .items)) ?? []
        estimatedCost = nil
        // requester nested object → extract name
        if let rc = try? c.nestedContainer(keyedBy: RequesterKeys.self, forKey: .requester) {
            requester = (try? rc.decode(String.self, forKey: .name)) ?? ""
        } else {
            requester = (try? c.decode(String.self, forKey: .requester)) ?? ""
        }
        title = items.first?.name ?? "採購需求"
        description = items
            .map { [$0.name, $0.quantity].compactMap { $0 }.joined(separator: " × ") }
            .joined(separator: "，")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let wireCat = PurchaseRequest.categoryToWire[category] ?? category
        try c.encode(wireCat, forKey: .category)
        try c.encode(items.isEmpty ? [PurchaseItem(name: title)] : items,
                     forKey: .items)
        try c.encode(notes, forKey: .note)
    }

    var statusColor: Color {
        switch status {
        case "pending":   return .orange
        case "approved":  return .green
        case "completed": return .blue
        case "rejected":  return .red
        case "withdrawn": return .gray
        default: return .gray
        }
    }

    var statusDisplayName: String {
        switch status {
        case "pending":   return String(localized: "待確認")
        case "approved":  return String(localized: "已核准")
        case "completed": return String(localized: "已完成")
        case "rejected":  return String(localized: "已拒絕")
        case "withdrawn": return String(localized: "已撤回")
        default:          return status
        }
    }

    var categoryIcon: String {
        switch category {
        case "食品": return "cart.fill"
        case "日用品": return "shippingbox.fill"
        case "醫療用品": return "cross.fill"
        default: return "bag.fill"
        }
    }

    static var samples: [PurchaseRequest] {
        [
            PurchaseRequest(id: UUID().uuidString, title: "電子血壓計（腕式）", category: "醫療用品",
                            description: "需要一組腕式血壓計，方便每日量測",
                            estimatedCost: 1280,
                            status: "待確認", createdAt: Date().addingTimeInterval(-3600),
                            requester: "Rita Santos",
                            notes: "奶奶最近血壓帶有漏氣現象，本的血壓計較腕式比比方便，適合居家日常監測，已來在藥局被認適合格醫療器材。",
                            items: [PurchaseItem(name: "電子血壓計（腕式）", quantity: "1")]),
            PurchaseRequest(id: UUID().uuidString, title: "購買優格和香蕉", category: "食品",
                            description: "爺爺喜歡的零食，一週份量",
                            estimatedCost: nil,
                            status: "已核准", createdAt: Date().addingTimeInterval(-86400),
                            requester: "Rita Santos", notes: "",
                            items: [PurchaseItem(name: "優格", quantity: "6 杯"),
                                    PurchaseItem(name: "香蕉", quantity: "1 串")]),
        ]
    }
}

// MARK: - Dynamic Translation
enum DynamicTranslation {
    static func displayText(
        original: String,
        translations: [String: String]?,
        language: String?
    ) -> String {
        guard let language,
              let translated = translations?[language],
              !translated.isEmpty else {
            return original
        }
        return translated
    }
}

private extension String {
    func strippingKnownPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        let value = dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func strippingKnownSuffix(_ suffix: String) -> String? {
        guard hasSuffix(suffix) else { return nil }
        let value = dropLast(suffix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// MARK: - AI Message
struct AIGeneratedDocument: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, Equatable {
        case careAnalysis = "care-analysis"
        case handoverReport = "handover-report"
        case subsidyForm = "subsidy-form"
    }

    var id: String
    var title: String
    var kind: Kind
    var body: String
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        kind: Kind,
        body: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.body = Self.plainTextBody(from: body)
        self.createdAt = createdAt
    }

    var plainText: String {
        "\(title)\n\n\(body)"
    }

    var fileName: String {
        let safeTitle = title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()
        let baseName = safeTitle.isEmpty ? kind.rawValue : safeTitle
        return "\(baseName)-\(id).txt"
    }

    func writeTemporaryFile(fileManager: FileManager = .default) throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("CareBridgeAIDocuments", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let url = directory.appendingPathComponent(fileName)
        try Data(plainText.utf8).write(to: url, options: .atomic)
        return url
    }

    static func careAnalysis(_ response: AICareAnalysisResponse) -> AIGeneratedDocument {
        AIGeneratedDocument(
            title: "照護報告",
            kind: .careAnalysis,
            body: response.analysis
        )
    }

    static func handoverReport(_ response: AIHandoverReportResponse) -> AIGeneratedDocument {
        let title = response.date.isEmpty ? "交接報告" : "交接報告 \(response.date)"
        return AIGeneratedDocument(
            title: title,
            kind: .handoverReport,
            body: response.report
        )
    }

    static func subsidyForm(_ response: AISubsidyFormResponse) -> AIGeneratedDocument {
        let title = response.templateName.flatMap { $0.isEmpty ? nil : $0 } ?? "補助表單"
        let body = response.formFields
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
        return AIGeneratedDocument(
            title: title,
            kind: .subsidyForm,
            body: body
        )
    }

    private static func plainTextBody(from source: String) -> String {
        var output = source.replacingOccurrences(of: "\r\n", with: "\n")
        output = replace(output, pattern: #"(?m)^\s*#{1,6}\s*"#, with: "")
        output = replace(output, pattern: #"(?m)^\s*[-*+]\s+"#, with: "• ")
        output = replace(output, pattern: #"(?m)^\s*>\s?"#, with: "")
        output = replace(output, pattern: #"```[a-zA-Z0-9_-]*\n?"#, with: "")
        output = output.replacingOccurrences(of: "```", with: "")
        output = replace(output, pattern: #"`([^`]*)`"#, with: "$1")
        output = replace(output, pattern: #"\*\*([^*]+)\*\*"#, with: "$1")
        output = replace(output, pattern: #"\*([^*\n]+)\*"#, with: "$1")
        output = replace(output, pattern: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1")
        output = replace(output, pattern: #"(?m)^\s*[-=]{3,}\s*$\n?"#, with: "")
        output = replace(output, pattern: #"\n{3,}"#, with: "\n\n")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(
        _ source: String,
        pattern: String,
        with template: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return source
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.stringByReplacingMatches(
            in: source,
            options: [],
            range: range,
            withTemplate: template
        )
    }
}

struct AIMessage: Identifiable, Codable {
    var id: String
    var content: String
    var isUser: Bool
    var timestamp: Date
    var document: AIGeneratedDocument? = nil

    static var samples: [AIMessage] {
        [
            AIMessage(id: UUID().uuidString, content: "請分析一下李奶奶過去三天的血壓趨勢。",
                      isUser: true, timestamp: Date().addingTimeInterval(-600)),
            AIMessage(id: UUID().uuidString, content: "根據過去72小時的數據顯示，李奶奶的血壓呈現小幅波動但總體趨於穩定。收縮壓在 **128-135 mmHg** 之間，舒張壓穩定在 **78-82 mmHg**。\n\n建議：當前狀態良好，請繼續保持低鹽飲食。",
                      isUser: false, timestamp: Date().addingTimeInterval(-550)),
            AIMessage(id: UUID().uuidString, content: "需要現在調整用藥嗎？",
                      isUser: true, timestamp: Date().addingTimeInterval(-300)),
        ]
    }
}

// MARK: - AI Tool Responses
struct FirstAidSource: Codable, Hashable {
    var title: String
    var source: String
}

struct FirstAidAnswer: Codable {
    var answer: String
    var sources: [FirstAidSource]
    var tokensUsed: Int
}

struct AICareAnalysisResponse: Codable {
    var analysis: String
    var periodDays: Int
    var tokensUsed: Int
}

struct AIHandoverReportResponse: Codable {
    var report: String
    var date: String
    var tokensUsed: Int
}

private enum DynamicFormValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: DynamicFormValue])
    case array([DynamicFormValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([String: DynamicFormValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([DynamicFormValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    var stringValue: String {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .object(let value):
            return value
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.stringValue)" }
                .joined(separator: "\n")
        case .array(let value):
            return value.map(\.stringValue).joined(separator: "\n")
        case .null:
            return ""
        }
    }
}

struct AISubsidyFormResponse: Codable {
    var formType: String
    var templateName: String?
    var templateSource: String?
    var formFields: [String: String]
    var tokensUsed: Int

    private enum CodingKeys: String, CodingKey {
        case formType, templateName, templateSource, formFields, tokensUsed
    }

    init(
        formType: String,
        templateName: String? = nil,
        templateSource: String? = nil,
        formFields: [String: String],
        tokensUsed: Int
    ) {
        self.formType = formType
        self.templateName = templateName
        self.templateSource = templateSource
        self.formFields = formFields
        self.tokensUsed = tokensUsed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formType = (try? container.decode(String.self, forKey: .formType)) ?? ""
        templateName = try? container.decodeIfPresent(String.self, forKey: .templateName)
        templateSource = try? container.decodeIfPresent(String.self, forKey: .templateSource)
        tokensUsed = (try? container.decode(Int.self, forKey: .tokensUsed)) ?? 0
        let rawFields = (try? container.decode([String: DynamicFormValue].self, forKey: .formFields)) ?? [:]
        formFields = rawFields.mapValues(\.stringValue)
    }
}

// MARK: - First Aid Scenario
struct FirstAidScenario: Identifiable, Codable {
    var id: String
    var title: String
    var icon: String
    var steps: [String]

    // Color is UI-only, not from backend
    var color: Color {
        switch title {
        case "昏厥", "胸痛", "出血": return .red
        case "跌倒", "嘔吐": return .orange
        case "呼吸困難": return .blue
        default: return .gray
        }
    }

    static var samples: [FirstAidScenario] {
        [
            FirstAidScenario(id: UUID().uuidString, title: "昏厥", icon: "person.fill.questionmark", steps: [
                "保持呼吸道通暢 — 請確保患者在堅固的平面上，輕輕抬起下巴，使頭部後仰。",
                "尋找 AED 設備 — 如果有旁人在場，請立即呼叫其尋找最近的自動體外除顫器 (AED)。",
                "準備胸外按壓 — 雙臂伸直，雙手叠扣，按壓位置在兩乳頭連線中點，按壓深度約 5 厘米。",
            ]),
            FirstAidScenario(id: UUID().uuidString, title: "胸痛", icon: "heart.fill", steps: [
                "立即讓患者坐下或躺下，保持安靜。",
                "撥打 119 急救電話。",
                "若患者有硝化甘油，協助其舌下含服。",
            ]),
            FirstAidScenario(id: UUID().uuidString, title: "跌倒", icon: "figure.fall", steps: [
                "不要立刻移動患者，評估意識狀態。",
                "檢查是否有明顯骨折或出血。",
                "若有意識但無法站立，撥打 119 並保持患者溫暖。",
            ]),
            FirstAidScenario(id: UUID().uuidString, title: "呼吸困難", icon: "lungs.fill", steps: [
                "協助患者採坐姿，身體稍微前傾。",
                "鬆開頸部衣物，確保呼吸道通暢。",
                "立即撥打 119。",
            ]),
            FirstAidScenario(id: UUID().uuidString, title: "嘔吐", icon: "mouth.fill", steps: [
                "讓患者側躺，防止吸入嘔吐物。",
                "保持頭部側向一方。",
                "清潔口腔，提供漱口水。",
            ]),
            FirstAidScenario(id: UUID().uuidString, title: "出血", icon: "drop.fill", steps: [
                "用乾淨的布料直接加壓止血。",
                "若出血不止，持續加壓並抬高傷肢。",
                "嚴重出血請立即撥打 119。",
            ]),
        ]
    }
}
