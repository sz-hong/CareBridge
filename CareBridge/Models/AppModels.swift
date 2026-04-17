import SwiftUI
import Foundation

// MARK: - User Roles
enum UserRole: String, CaseIterable, Codable {
    case caregiver = "caregiver"
    case family = "family_member"
    case elder = "elder"

    var displayName: String {
        switch self {
        case .caregiver: return "看護"
        case .family:    return "家屬"
        case .elder:     return "長者"
        }
    }
}

// MARK: - User Profile
struct FamilyInfo: Codable {
    var id: String
    var name: String
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
        case flatFamilyId   = "familyId"
        case flatFamilyName = "familyName"
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
            family = FamilyInfo(id: fid, name: fname)
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
    var timestamp: Date
    var isAbnormal: Bool

    init(id: String, heartRate: Int, bloodOxygen: Double,
         bloodPressureSystolic: Int, bloodPressureDiastolic: Int,
         bloodSugar: Double, temperature: Double, steps: Int,
         timestamp: Date, isAbnormal: Bool) {
        self.id = id; self.heartRate = heartRate; self.bloodOxygen = bloodOxygen
        self.bloodPressureSystolic = bloodPressureSystolic
        self.bloodPressureDiastolic = bloodPressureDiastolic
        self.bloodSugar = bloodSugar; self.temperature = temperature
        self.steps = steps; self.timestamp = timestamp; self.isAbnormal = isAbnormal
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
        heartRate   = hr?.value.map { Int($0) } ?? 0
        bloodOxygen = ox?.value ?? 0
        steps       = st?.value.map { Int($0) } ?? 0
        // Backend HealthData has no blood pressure / sugar / temperature types in current schema
        bloodPressureSystolic = 0
        bloodPressureDiastolic = 0
        bloodSugar  = 0
        temperature = 0
        timestamp   = hr?.recordedAt ?? ox?.recordedAt ?? st?.recordedAt ?? Date()
        id          = hr?.id ?? ox?.id ?? st?.id ?? UUID().uuidString
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

    /// Returns translated text for the given language, or nil if it
    /// matches the original content (no point showing a duplicate).
    func translation(for language: String?) -> String? {
        guard let language, let dict = translations, let value = dict[language] else { return nil }
        return value == content ? nil : value
    }

    // MARK: Custom Coding (API field mapping)
    private enum CodingKeys: String, CodingKey {
        case id, content, translations, isMe, senderRole, imageURL
        case sender
        case timestamp = "sentAt"   // API: sent_at → convertFromSnakeCase → sentAt
    }
    private enum SenderKeys: String, CodingKey { case name, id }

    init(id: String, sender: String, senderId: String? = nil, senderRole: UserRole,
         content: String, translations: [String: String]?, timestamp: Date,
         isMe: Bool, imageURL: String? = nil) {
        self.id = id; self.sender = sender; self.senderId = senderId
        self.senderRole = senderRole
        self.content = content; self.translations = translations
        self.timestamp = timestamp; self.isMe = isMe; self.imageURL = imageURL
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
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(content, forKey: .content)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encodeIfPresent(imageURL, forKey: .imageURL)
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

    var displayName: String {
        switch self {
        case .medication: return "用藥"
        case .vital:      return "生理"
        case .meal:       return "飲食"
        case .activity:   return "活動"
        case .note:       return "備註"
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
    /// Structured vitals — populated for .vital entries so HomeView can
    /// show the latest reading without regex-parsing `detail`.
    var bloodPressureSystolic: Int? = nil
    var bloodPressureDiastolic: Int? = nil

    // MARK: Custom Coding
    private enum CodingKeys: String, CodingKey {
        case id, type, content, timestamp
        case photoUrl   // API: photo_url → convertFromSnakeCase → photoUrl
    }

    // Nested content fields (covers all care log types)
    private struct Content: Codable {
        var medicationName: String?
        var dosage: String?
        var bloodPressureSystolic: Double?
        var bloodPressureDiastolic: Double?
        var bloodSugar: Double?
        var temperature: Double?
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
            case medicationName, dosage, note, description, appetite, temperature, text
            case bloodPressureSystolic, bloodPressureDiastolic
            case bloodSugar, mealType, activityType, durationMinutes, textTranslated
        }
    }

    init(id: String, type: CareLogType, title: String, detail: String,
         timestamp: Date, hasPhoto: Bool,
         bloodPressureSystolic: Int? = nil,
         bloodPressureDiastolic: Int? = nil) {
        self.id = id; self.type = type; self.title = title
        self.detail = detail; self.timestamp = timestamp; self.hasPhoto = hasPhoto
        self.bloodPressureSystolic = bloodPressureSystolic
        self.bloodPressureDiastolic = bloodPressureDiastolic
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(String.self, forKey: .id)
        type      = try c.decode(CareLogType.self, forKey: .type)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        hasPhoto  = (try? c.decodeIfPresent(String.self, forKey: .photoUrl)) != nil

        let content = (try? c.decode(Content.self, forKey: .content)) ?? Content()
        switch type {
        case .medication:
            title  = content.medicationName ?? "用藥紀錄"
            detail = [content.dosage, content.note].compactMap { $0 }.joined(separator: "｜")
        case .vital:
            title  = "生理指標測量"
            var parts: [String] = []
            if let s = content.bloodPressureSystolic, let d = content.bloodPressureDiastolic {
                parts.append("血壓 \(Int(s))/\(Int(d)) mmHg")
                bloodPressureSystolic  = Int(s)
                bloodPressureDiastolic = Int(d)
            }
            if let bs = content.bloodSugar { parts.append("血糖 \(bs)") }
            if let t  = content.temperature { parts.append("體溫 \(t)°C") }
            if let n  = content.note        { parts.append(n) }
            detail = parts.joined(separator: "｜")
        case .meal:
            title  = "飲食紀錄"
            detail = [content.description, content.appetite.map { "食慾：\($0)" }].compactMap { $0 }.joined(separator: "｜")
        case .activity:
            title  = content.activityType ?? "活動紀錄"
            detail = content.durationMinutes.map { "持續 \($0) 分鐘" } ?? (content.note ?? "")
        case .note:
            title  = "備註"
            detail = content.text ?? content.textTranslated ?? ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(timestamp, forKey: .timestamp)
        // Encode minimal content based on type. AnyCodable-free: use a mixed dict
        // so numeric vitals stay numeric instead of being stringified.
        var content: [String: AnyEncodable] = [:]
        switch type {
        case .note:       content["text"]        = AnyEncodable(detail)
        case .vital:
            if let s = bloodPressureSystolic  { content["blood_pressure_systolic"]  = AnyEncodable(s) }
            if let d = bloodPressureDiastolic { content["blood_pressure_diastolic"] = AnyEncodable(d) }
            content["note"] = AnyEncodable(detail)
        case .meal:       content["description"] = AnyEncodable(detail)
        case .activity:   content["note"]        = AnyEncodable(detail)
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
@Observable
class UserStore {
    var currentUser: UserProfile? = nil
    var familyMembers: [UserProfile] = []
    var isLoading = false
    private let service: DataService

    init(service: DataService = MockDataService()) { self.service = service }

    /// Called immediately after login — pre-populates profile from AuthResponse
    func populate(from authResponse: AuthResponse) {
        currentUser = authResponse.user
    }

    /// Fetches up-to-date profile + family members from API
    func load() {
        isLoading = true
        Task {
            do {
                async let profile = service.fetchProfile()
                async let members = service.fetchFamilyMembers()
                let (p, m) = try await (profile, members)
                await MainActor.run {
                    currentUser = p
                    familyMembers = m
                }
            } catch {
                print("[UserStore] fetch failed: \(error)")
            }
            await MainActor.run { isLoading = false }
        }
    }
}

// MARK: - Care Log Store (shared state → API synced)
@Observable
class CareLogStore {
    var entries: [CareLogEntry] = []
    var isLoading = false
    private let service: DataService

    init(service: DataService = MockDataService()) {
        self.service = service
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        Task { @MainActor in
            do {
                entries = try await service.fetchCareLogEntries(date: nil)
            } catch {
                print("[CareLogStore] fetch failed: \(error)")
            }
            isLoading = false
        }
    }

    func addEntry(_ entry: CareLogEntry) {
        entries.insert(entry, at: 0)
        Task {
            do {
                _ = try await service.createCareLogEntry(entry)
            } catch {
                print("[CareLogStore] create failed: \(error)")
            }
        }
    }
}

// MARK: - Todo Store (shared state → API synced)
@Observable
class TodoStore {
    var todos: [TodoItem] = []
    var isLoading = false
    private let service: DataService

    init(service: DataService = MockDataService()) {
        self.service = service
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        Task { @MainActor in
            do {
                todos = try await service.fetchTodos()
            } catch {
                print("[TodoStore] fetch failed: \(error)")
            }
            isLoading = false
        }
    }

    func addTodo(_ todo: TodoItem) {
        todos.insert(todo, at: 0)
        Task {
            do {
                _ = try await service.createTodo(todo)
            } catch {
                print("[TodoStore] create failed: \(error)")
            }
        }
    }

    func updateTodo(_ todo: TodoItem) {
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[index] = todo
        }
        Task {
            do {
                _ = try await service.updateTodo(todo)
            } catch {
                print("[TodoStore] update failed: \(error)")
            }
        }
    }
}

// MARK: - Calendar Store (shared state → API synced)
@Observable
class CalendarStore {
    var events: [CalendarEvent] = []
    var isLoading = false
    private let service: DataService

    init(service: DataService = MockDataService()) {
        self.service = service
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        Task { @MainActor in
            do {
                events = try await service.fetchCalendarEvents(month: Date())
            } catch {
                print("[CalendarStore] fetch failed: \(error)")
            }
            isLoading = false
        }
    }

    func addEvent(_ event: CalendarEvent) {
        events.append(event)
        Task {
            do {
                _ = try await service.createCalendarEvent(event)
            } catch {
                print("[CalendarStore] create failed: \(error)")
            }
        }
    }

    func addEvents(_ newEvents: [CalendarEvent]) {
        events.append(contentsOf: newEvents)
        Task {
            do {
                _ = try await service.createCalendarEvents(newEvents)
            } catch {
                print("[CalendarStore] batch create failed: \(error)")
            }
        }
    }
}

// MARK: - Medication Store (shared state → API synced)
@Observable
class MedicationStore {
    var medications: [Medication] = []
    var doses: [DoseEntry] = []
    var isLoading = false
    private let service: DataService

    init(service: DataService = MockDataService()) {
        self.service = service
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        Task { @MainActor in
            do {
                async let medsTask = service.fetchMedications(elderId: "")
                async let confsTask = service.fetchTodayConfirmations()
                let (fetchedMeds, confs) = try await (medsTask, confsTask)
                medications = fetchedMeds
                
                // Build today's dose timeline
                var newDoses: [DoseEntry] = []
                for med in medications {
                    for time in med.times {
                        let isConfirmed = confs.contains { $0.medication == med.id && $0.scheduledTime == time }
                        newDoses.append(DoseEntry(medicationId: med.id, time: time, name: "\(med.nameTranslated) \(med.dosage)", isDone: isConfirmed))
                    }
                }
                // Sort chronologically (e.g. 08:00 before 20:00)
                doses = newDoses.sorted { $0.time < $1.time }
                
            } catch {
                print("[MedicationStore] fetch failed: \(error)")
            }
            isLoading = false
        }
    }

    func addMedication(_ medication: Medication) {
        medications.append(medication)
        // Add dose entries for today's timeline
        for time in medication.times {
            doses.append(DoseEntry(medicationId: medication.id, time: time, name: "\(medication.nameTranslated) \(medication.dosage)", isDone: false))
        }
        doses.sort { $0.time < $1.time }
        Task {
            do {
                _ = try await service.createMedication(medication)
            } catch {
                print("[MedicationStore] create failed: \(error)")
            }
        }
    }

    func markDoseTaken(index: Int) {
        guard index < doses.count else { return }
        doses[index].isDone = true
        let dose = doses[index]
        let request = ConfirmMedicationRequest(scheduledTime: dose.time, photoUrl: nil, note: nil)
        Task {
            do {
                _ = try await service.confirmMedication(id: dose.medicationId, request: request)
            } catch {
                print("[MedicationStore] mark dose taken failed: \(error)")
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
    var isActive: Bool               // API: is_active
    var startDate: Date              // API: start_date (yyyy-MM-dd)
    var endDate: Date?               // API: end_date
    var reminderEnabled: Bool        // API: reminder_enabled

    private enum CodingKeys: String, CodingKey {
        // All snake_case keys auto-converted by .convertFromSnakeCase
        case id, name, dosage, frequency, times, instructions
        case nameTranslated, isActive, startDate, endDate, reminderEnabled
    }

    init(id: String = UUID().uuidString, name: String, nameTranslated: String,
         dosage: String, frequency: String, times: [String], instructions: String,
         isActive: Bool = true, startDate: Date = Date(), endDate: Date? = nil,
         reminderEnabled: Bool = true) {
        self.id = id; self.name = name; self.nameTranslated = nameTranslated
        self.dosage = dosage; self.frequency = frequency; self.times = times
        self.instructions = instructions; self.isActive = isActive
        self.startDate = startDate; self.endDate = endDate; self.reminderEnabled = reminderEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(String.self, forKey: .id)
        name           = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        dosage         = (try? c.decodeIfPresent(String.self, forKey: .dosage)) ?? ""
        frequency      = (try? c.decodeIfPresent(String.self, forKey: .frequency)) ?? "daily"
        times          = (try? c.decodeIfPresent([String].self, forKey: .times)) ?? []
        instructions   = (try? c.decodeIfPresent(String.self, forKey: .instructions)) ?? ""
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
    /// 去背後的發票圖片，僅存在記憶體中（不序列化至 JSON/API）
    var receiptImage: UIImage? = nil

    enum CodingKeys: String, CodingKey {
        case id, date, items, imageUrl
        case title = "storeName"       // API: store_name → convertFromSnakeCase → storeName
        case amount = "totalAmount"    // API: total_amount → totalAmount
        // `category` is UI-only — backend stores category per item inside `items` JSONB.
    }

    init(id: String, title: String, amount: Double, category: String, date: Date,
         hasReceipt: Bool, imageUrl: String? = nil, receiptImage: UIImage? = nil) {
        self.id = id; self.title = title; self.amount = amount
        self.category = category; self.date = date; self.hasReceipt = hasReceipt
        self.imageUrl = imageUrl
        self.receiptImage = receiptImage
    }

    // Backend stores per-item category as enum keys inside `items` JSONB.
    // UI uses Chinese labels from OCRConfirmationView's picker; translate both ways.
    static let categoryToWire: [String: String] = [
        "醫療保健": "medical",
        "日常飲食": "food",
        "生活用品": "daily",
        "交通":    "transport",
        "其他":    "other",
    ]
    static let wireToCategory: [String: String] = [
        "medical":   "醫療保健",
        "food":      "日常飲食",
        "daily":     "生活用品",
        "transport": "交通",
        "other":     "其他",
    ]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(String.self, forKey: .id)
        title    = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        // Backend has no top-level `category`; category is a per-item field inside items JSONB.
        // Read first item's category and normalize backend enum keys to UI labels.
        if let items = try? c.decodeIfPresent([[String: String]].self, forKey: .items),
           let raw = items.first?["category"], !raw.isEmpty {
            category = Expense.wireToCategory[raw] ?? raw
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
        // image_url non-nil means receipt exists
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        hasReceipt = (imageUrl != nil)
    }

    func encode(to encoder: Encoder) throws {
        // Matches backend CreateExpenseSerializer: store_name, date, items, total_amount, image_url.
        // Category is embedded inside `items` per backend schema.
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title,  forKey: .title)
        try c.encode(amount, forKey: .amount)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        try c.encode(df.string(from: date), forKey: .date)
        let wireCat = Expense.categoryToWire[category] ?? category
        let item: [String: String] = [
            "name": title,
            "category": wireCat,
        ]
        try c.encode([item], forKey: .items)
        try c.encodeIfPresent(imageUrl, forKey: .imageUrl)
    }

    var categoryIcon: String {
        switch category {
        case "醫療保健": return "cross.fill"
        case "日常飲食": return "fork.knife"
        case "生活用品": return "shippingbox.fill"
        case "交通":    return "car.fill"
        case "其他":    return "bag.fill"
        default:        return "bag.fill"
        }
    }

    var categoryColor: Color {
        switch category {
        case "醫療保健": return Color(red: 0.0, green: 0.55, blue: 0.6)
        case "日常飲食": return .orange
        case "生活用品": return .purple
        case "交通":    return .blue
        case "其他":    return .pink
        default:        return .gray
        }
    }

    var categoryDisplayName: String { category }

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

    static var categoryBreakdown: [(String, Double, Color)] {
        [
            ("醫療保健", 45, Color(red: 0.0, green: 0.55, blue: 0.6)),
            ("日常飲食", 25, .orange),
            ("生活用品", 20, .purple),
            ("其他支出", 10, .gray),
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
        case .high:   return "高"
        case .medium: return "中"
        case .low:    return "低"
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
    var assignee: String    // API: assignee.name (read-only display)
    var assigneeId: String? // API: assignee.id — required by CreateTodoSerializer as `assignee_id`
    var priority: Priority
    var dueDate: Date?      // API: due_date (date-only string)
    var isCompleted: Bool   // API: status == "completed"

    private enum CodingKeys: String, CodingKey {
        // All snake_case keys auto-converted by .convertFromSnakeCase
        case id, title, priority, assignee, status
        case dueDate, assigneeId
    }
    private enum AssigneeKeys: String, CodingKey { case id, name }

    init(id: String, title: String, assignee: String, priority: Priority,
         dueDate: Date?, isCompleted: Bool, assigneeId: String? = nil) {
        self.id = id; self.title = title; self.assignee = assignee
        self.assigneeId = assigneeId
        self.priority = priority; self.dueDate = dueDate; self.isCompleted = isCompleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(String.self, forKey: .id)
        title    = try c.decode(String.self, forKey: .title)
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
    var date: Date      // API: start_time
    var location: String?
    var type: String    // API types: "medical" / "medication" / "rehab" / "leave" / "personal" / "other"

    private enum CodingKeys: String, CodingKey {
        case id, title, location, type
        case date = "startTime"   // API: start_time → convertFromSnakeCase → startTime
    }

    init(id: String, title: String, date: Date, location: String?, type: String) {
        self.id = id; self.title = title; self.date = date
        self.location = location; self.type = type
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(String.self, forKey: .id)
        title    = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
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

    var displayName: String {
        switch self {
        case .pending:  return "待審核"
        case .approved: return "已核准"
        case .rejected: return "已駁回"
        }
    }

    var color: Color {
        switch self {
        case .pending:  return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }
}

struct LeaveRequest: Identifiable, Codable {
    var id: String
    var type: String        // API: "personal" / "sick" / "emergency"
    var startDate: Date     // API: start_date (date-only)
    var endDate: Date       // API: end_date (date-only)
    var reason: String
    var status: LeaveStatus

    private enum CodingKeys: String, CodingKey {
        // All snake_case keys auto-converted by .convertFromSnakeCase
        case id, type, reason, status, startDate, endDate
    }

    init(id: String, type: String, startDate: Date, endDate: Date,
         reason: String, status: LeaveStatus) {
        self.id = id; self.type = type; self.startDate = startDate
        self.endDate = endDate; self.reason = reason; self.status = status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id     = try c.decode(String.self, forKey: .id)
        type   = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "personal"
        reason = (try? c.decodeIfPresent(String.self, forKey: .reason)) ?? ""
        status = (try? c.decodeIfPresent(LeaveStatus.self, forKey: .status)) ?? .pending
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let s1 = (try? c.decodeIfPresent(String.self, forKey: .startDate)) ?? ""
        let s2 = (try? c.decodeIfPresent(String.self, forKey: .endDate)) ?? ""
        startDate = fmt.date(from: s1) ?? Date()
        endDate   = fmt.date(from: s2) ?? startDate
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
        case "personal", "事假": return "事假"
        case "sick",     "病假": return "病假"
        case "emergency","緊急": return "緊急假"
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

    private enum CodingKeys: String, CodingKey {
        case id, title, category
        case fileSizeBytes = "fileSize"    // API: file_size → convertFromSnakeCase → fileSize
        case uploadDate    = "createdAt"   // API: created_at → createdAt
    }

    init(id: String, title: String, category: String, fileSize: String, uploadDate: Date, localURL: URL? = nil) {
        self.id = id; self.title = title; self.category = category
        self.fileSize = fileSize; self.uploadDate = uploadDate; self.localURL = localURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(String.self, forKey: .id)
        title      = try c.decode(String.self, forKey: .title)
        category   = try c.decode(String.self, forKey: .category)
        uploadDate = try c.decode(Date.self, forKey: .uploadDate)
        localURL   = nil
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
        case "insurance":  return "保險"
        case "medical":    return "醫療"
        case "id_document": return "證件"
        case "contract":   return "合約"
        case "other":      return "其他"
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
    case leaveApproved       = "leave_approved"
    case leaveRejected       = "leave_rejected"
    case purchase            = "board_request"
    case purchaseApproved    = "board_approved"
    case expenseScanned      = "expense_scanned"
    case sos                 = "sos_triggered"
    case eventReminder       = "event_reminder"
    case todo                = "todo_assigned"
    case chat                = "chat_message"

    var icon: String {
        switch self {
        case .health: return "heart.fill"
        case .medication, .medicationConfirmed: return "pills.fill"
        case .leave, .leaveApproved, .leaveRejected: return "calendar.badge.exclamationmark"
        case .chat: return "message.fill"
        case .sos: return "sos"
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
        case .leave: return .orange
        case .leaveApproved: return .green
        case .leaveRejected: return .red
        case .chat: return .green
        case .sos: return .red
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

    enum CodingKeys: String, CodingKey {
        case id, title, body
        case category = "type"    // API: "type" field → renamed to category in Swift
        case isRead               // API: is_read → convertFromSnakeCase → isRead
        case timestamp = "createdAt"  // API: created_at → createdAt
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
    var items: [PurchaseItem]   // API: items JSONB

    struct PurchaseItem: Codable, Hashable {
        var name: String
        var nameTranslated: String?
        var quantity: String?

        enum CodingKeys: String, CodingKey {
            // name_translated → convertFromSnakeCase → nameTranslated
            case name, quantity, nameTranslated
        }
    }

    private enum CodingKeys: String, CodingKey {
        // created_at → convertFromSnakeCase → createdAt
        case id, category, status, items, requester, createdAt, note
    }
    private enum RequesterKeys: String, CodingKey { case name }

    init(id: String, title: String, category: String, description: String,
         estimatedCost: Double?, status: String, createdAt: Date,
         requester: String, notes: String, items: [PurchaseItem] = []) {
        self.id = id; self.title = title; self.category = category
        self.description = description; self.estimatedCost = estimatedCost
        self.status = status; self.createdAt = createdAt
        self.requester = requester; self.notes = notes; self.items = items
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
        try c.encode(items.isEmpty ? [PurchaseItem(name: title, nameTranslated: nil, quantity: nil)] : items,
                     forKey: .items)
        try c.encode(notes, forKey: .note)
    }

    var statusColor: Color {
        switch status {
        case "pending":   return .orange
        case "approved":  return .green
        case "completed": return .blue
        case "rejected":  return .red
        default: return .gray
        }
    }

    var statusDisplayName: String {
        switch status {
        case "pending":   return "待確認"
        case "approved":  return "已核准"
        case "completed": return "已完成"
        case "rejected":  return "已駁回"
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
                            items: [PurchaseItem(name: "電子血壓計（腕式）", nameTranslated: nil, quantity: "1")]),
            PurchaseRequest(id: UUID().uuidString, title: "購買優格和香蕉", category: "食品",
                            description: "爺爺喜歡的零食，一週份量",
                            estimatedCost: nil,
                            status: "已核准", createdAt: Date().addingTimeInterval(-86400),
                            requester: "Rita Santos", notes: "",
                            items: [PurchaseItem(name: "優格", nameTranslated: nil, quantity: "6 杯"),
                                    PurchaseItem(name: "香蕉", nameTranslated: nil, quantity: "1 串")]),
        ]
    }
}

// MARK: - AI Message
struct AIMessage: Identifiable, Codable {
    var id: String
    var content: String
    var isUser: Bool
    var timestamp: Date

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

