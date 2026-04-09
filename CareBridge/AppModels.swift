import SwiftUI
import Foundation

// MARK: - User Roles
enum UserRole: String, CaseIterable {
    case caregiver = "看護"
    case family = "家屬"
    case elder = "長者"
}

// MARK: - Health Data
struct HealthData: Identifiable {
    let id = UUID()
    var heartRate: Int
    var bloodOxygen: Double
    var bloodPressureSystolic: Int
    var bloodPressureDiastolic: Int
    var bloodSugar: Double
    var temperature: Double
    var steps: Int
    var timestamp: Date
    var isAbnormal: Bool

    static var sample: HealthData {
        HealthData(
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

// MARK: - Chat Message
struct ChatMessage: Identifiable {
    let id = UUID()
    var sender: String
    var senderRole: UserRole
    var content: String
    var translatedContent: String?
    var timestamp: Date
    var isMe: Bool
    var imageURL: String?

    static var samples: [ChatMessage] {
        [
            ChatMessage(sender: "Rita Santos", senderRole: .caregiver,
                        content: "Sudah minum obat pagi.",
                        translatedContent: "早上的藥已服用完畢。",
                        timestamp: Date().addingTimeInterval(-3600), isMe: false),
            ChatMessage(sender: "林小明", senderRole: .family,
                        content: "謝謝，今天狀況如何？",
                        translatedContent: "Terima kasih, bagaimana keadaan hari ini?",
                        timestamp: Date().addingTimeInterval(-3200), isMe: true),
            ChatMessage(sender: "Rita Santos", senderRole: .caregiver,
                        content: "爺爺精神很好，有散步30分鐘。",
                        translatedContent: "Kakek semangat, sudah jalan 30 menit.",
                        timestamp: Date().addingTimeInterval(-3000), isMe: false),
            ChatMessage(sender: "林大華", senderRole: .family,
                        content: "很好！晚上記得提醒他吃藥",
                        translatedContent: nil,
                        timestamp: Date().addingTimeInterval(-2400), isMe: false),
        ]
    }
}

// MARK: - Chat Room
struct ChatRoom: Identifiable {
    let id = UUID()
    var name: String
    var participants: [String]
    var lastMessage: String
    var lastMessageTime: Date
    var unreadCount: Int
    var isGroup: Bool
    var avatarIcon: String

    static var samples: [ChatRoom] {
        [
            ChatRoom(name: "王家照護群", participants: ["林小明", "林大華", "Rita Santos"],
                     lastMessage: "爸爸今天血壓正常", lastMessageTime: Date().addingTimeInterval(-1200),
                     unreadCount: 3, isGroup: true, avatarIcon: "person.3.fill"),
            ChatRoom(name: "Siti 小華", participants: ["林小明", "Siti"],
                     lastMessage: "已經吃過午餐了", lastMessageTime: Date().addingTimeInterval(-86400),
                     unreadCount: 0, isGroup: false, avatarIcon: "person.fill"),
        ]
    }
}

// MARK: - Care Log
enum CareLogType: String, CaseIterable {
    case medication = "用藥"
    case vital = "生理"
    case meal = "飲食"
    case activity = "活動"
    case note = "備註"

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

struct CareLogEntry: Identifiable {
    let id = UUID()
    var type: CareLogType
    var title: String
    var detail: String
    var timestamp: Date
    var hasPhoto: Bool

    static var samples: [CareLogEntry] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        return [
            CareLogEntry(type: .vital, title: "晨間生理指標測量",
                         detail: "血壓 118/75 mmHg｜心率 72 bpm",
                         timestamp: today.addingTimeInterval(8.5 * 3600), hasPhoto: false),
            CareLogEntry(type: .medication, title: "晨間用藥提醒",
                         detail: "阿斯匹靈 (100mg) - 飯後服用",
                         timestamp: today.addingTimeInterval(8 * 3600 + 300), hasPhoto: false),
            CareLogEntry(type: .meal, title: "營養早餐",
                         detail: "白粥、蒸蛋、菠菜，食慾良好，全部完食",
                         timestamp: today.addingTimeInterval(7.5 * 3600), hasPhoto: true),
            CareLogEntry(type: .activity, title: "晨間散步",
                         detail: "花園散步 30 分鐘，約 1,200 步，狀態良好",
                         timestamp: today.addingTimeInterval(7 * 3600), hasPhoto: false),
            CareLogEntry(type: .note, title: "晚間就寢紀錄",
                         detail: "21:00 安靜入睡，無異常",
                         timestamp: yesterday.addingTimeInterval(21 * 3600), hasPhoto: false),
        ]
    }
}

// MARK: - Medication
struct Medication: Identifiable {
    let id = UUID()
    var name: String
    var nameTranslated: String
    var dosage: String
    var frequency: String
    var times: [String]
    var notes: String
    var isActive: Bool

    static var samples: [Medication] {
        [
            Medication(name: "Amlodipine", nameTranslated: "氨氯地平",
                       dosage: "5mg", frequency: "每日一次", times: ["08:00"],
                       notes: "飯後服用，注意低血壓", isActive: true),
            Medication(name: "Metformin", nameTranslated: "二甲雙胍",
                       dosage: "500mg", frequency: "每日兩次", times: ["08:00", "18:00"],
                       notes: "飯中服用", isActive: true),
            Medication(name: "Aspirin", nameTranslated: "阿斯匹靈",
                       dosage: "100mg", frequency: "每日一次", times: ["08:00"],
                       notes: "飯後服用，勿空腹", isActive: true),
        ]
    }
}

// MARK: - Expense
struct Expense: Identifiable {
    let id = UUID()
    var title: String
    var amount: Double
    var category: String
    var date: Date
    var hasReceipt: Bool

    var categoryIcon: String {
        switch category {
        case "醫療保健": return "cross.fill"
        case "日常飲食": return "fork.knife"
        case "生活用品": return "shippingbox.fill"
        default: return "bag.fill"
        }
    }

    var categoryColor: Color {
        switch category {
        case "醫療保健": return Color(red: 0.0, green: 0.55, blue: 0.6)
        case "日常飲食": return .orange
        case "生活用品": return .purple
        default: return .gray
        }
    }

    static var samples: [Expense] {
        [
            Expense(title: "健檢費用 - 慈濟醫院", amount: 12000, category: "醫療保健",
                    date: Date().addingTimeInterval(-3600 * 3), hasReceipt: true),
            Expense(title: "全聯福利中心 - 食品", amount: 1450, category: "日常飲食",
                    date: Date().addingTimeInterval(-3600 * 6), hasReceipt: true),
            Expense(title: "成人紙尿褲 - 屈臣氏", amount: 3200, category: "生活用品",
                    date: Date().addingTimeInterval(-86400), hasReceipt: true),
            Expense(title: "處方藥費 - 杏一藥局", amount: 850, category: "醫療保健",
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
enum Priority: String, CaseIterable {
    case high = "高"
    case medium = "中"
    case low = "低"

    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }
}

struct TodoItem: Identifiable {
    let id = UUID()
    var title: String
    var assignee: String
    var priority: Priority
    var dueDate: Date?
    var isCompleted: Bool

    static var samples: [TodoItem] {
        [
            TodoItem(title: "安排回診掛號（台大醫院心臟科）",
                     assignee: "林小明", priority: .high,
                     dueDate: Date().addingTimeInterval(86400 * 3), isCompleted: false),
            TodoItem(title: "補購復健護具",
                     assignee: "Rita Santos", priority: .medium,
                     dueDate: Date().addingTimeInterval(86400), isCompleted: false),
            TodoItem(title: "更新健保卡資料",
                     assignee: "林大華", priority: .low,
                     dueDate: nil, isCompleted: true),
        ]
    }
}

// MARK: - Calendar Event
struct CalendarEvent: Identifiable {
    let id = UUID()
    var title: String
    var date: Date
    var location: String?
    var type: String

    var typeIcon: String {
        switch type {
        case "回診": return "stethoscope"
        case "復健": return "figure.walk"
        case "用藥": return "pills.fill"
        default: return "calendar"
        }
    }

    var typeColor: Color {
        switch type {
        case "回診": return Color(red: 0.0, green: 0.55, blue: 0.6)
        case "復健": return .green
        case "用藥": return .blue
        default: return .gray
        }
    }

    static var samples: [CalendarEvent] {
        [
            CalendarEvent(title: "心臟科回診", date: Date().addingTimeInterval(86400 * 5),
                          location: "台大醫院心臟科門診", type: "回診"),
            CalendarEvent(title: "物理治療復健", date: Date().addingTimeInterval(86400 * 2),
                          location: "復健科", type: "復健"),
            CalendarEvent(title: "服藥提醒", date: Date().addingTimeInterval(3600 * 2),
                          location: nil, type: "用藥"),
        ]
    }
}

// MARK: - Leave Request
enum LeaveStatus: String {
    case pending = "待審核"
    case approved = "已核准"
    case rejected = "已駁回"

    var color: Color {
        switch self {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }
}

struct LeaveRequest: Identifiable {
    let id = UUID()
    var type: String
    var startDate: Date
    var endDate: Date
    var reason: String
    var status: LeaveStatus

    static var samples: [LeaveRequest] {
        [
            LeaveRequest(type: "事假",
                         startDate: Date().addingTimeInterval(86400 * 10),
                         endDate: Date().addingTimeInterval(86400 * 12),
                         reason: "返鄉探親", status: .pending),
            LeaveRequest(type: "病假",
                         startDate: Date().addingTimeInterval(-86400 * 7),
                         endDate: Date().addingTimeInterval(-86400 * 6),
                         reason: "就醫", status: .approved),
        ]
    }
}

// MARK: - Document
struct AppDocument: Identifiable {
    let id = UUID()
    var title: String
    var category: String
    var fileSize: String
    var uploadDate: Date

    var categoryIcon: String {
        switch category {
        case "保險": return "shield.fill"
        case "醫療": return "cross.fill"
        case "證件": return "creditcard.fill"
        case "合約": return "doc.text.fill"
        default: return "folder.fill"
        }
    }

    var categoryColor: Color {
        switch category {
        case "保險": return .blue
        case "醫療": return .red
        case "證件": return .orange
        case "合約": return .purple
        default: return .gray
        }
    }

    static var samples: [AppDocument] {
        [
            AppDocument(title: "長照保險單2024", category: "保險",
                        fileSize: "2.3 MB", uploadDate: Date().addingTimeInterval(-86400 * 30)),
            AppDocument(title: "最新健康檢查報告", category: "醫療",
                        fileSize: "5.1 MB", uploadDate: Date().addingTimeInterval(-86400 * 14)),
            AppDocument(title: "身份證正反面", category: "證件",
                        fileSize: "0.8 MB", uploadDate: Date().addingTimeInterval(-86400 * 60)),
        ]
    }
}

// MARK: - Notification
enum NotificationCategory: String {
    case health = "健康警示"
    case medication = "用藥提醒"
    case leave = "請假申請"
    case chat = "聊天訊息"
    case sos = "SOS 緊急"
    case todo = "代辦指派"
    case purchase = "採購需求"

    var icon: String {
        switch self {
        case .health: return "heart.fill"
        case .medication: return "pills.fill"
        case .leave: return "calendar.badge.exclamationmark"
        case .chat: return "message.fill"
        case .sos: return "sos"
        case .todo: return "checkmark.circle.fill"
        case .purchase: return "cart.fill"
        }
    }

    var color: Color {
        switch self {
        case .health: return .red
        case .medication: return Color(red: 0.0, green: 0.55, blue: 0.6)
        case .leave: return .orange
        case .chat: return .green
        case .sos: return .red
        case .todo: return .purple
        case .purchase: return .blue
        }
    }
}

struct AppNotification: Identifiable {
    let id = UUID()
    var category: NotificationCategory
    var title: String
    var body: String
    var timestamp: Date
    var isRead: Bool

    static var samples: [AppNotification] {
        [
            AppNotification(category: .health, title: "心率異常警示",
                            body: "爸爸心率達到 112 bpm，超出正常範圍",
                            timestamp: Date().addingTimeInterval(-1800), isRead: false),
            AppNotification(category: .medication, title: "用藥提醒",
                            body: "下午 2:00 Metformin 500mg 服藥時間到",
                            timestamp: Date().addingTimeInterval(-3600), isRead: false),
            AppNotification(category: .leave, title: "請假申請",
                            body: "Rita Santos 申請 4/20-4/22 事假，請審核",
                            timestamp: Date().addingTimeInterval(-7200), isRead: true),
            AppNotification(category: .purchase, title: "採購需求",
                            body: "Rita Santos 申請補購成人尿布 x 2 包",
                            timestamp: Date().addingTimeInterval(-10800), isRead: true),
        ]
    }
}

// MARK: - Message Board (Purchase Requests)
struct PurchaseRequest: Identifiable {
    let id = UUID()
    var title: String
    var category: String
    var description: String
    var estimatedCost: Double?
    var status: String
    var createdAt: Date
    var requester: String
    var notes: String

    var statusColor: Color {
        switch status {
        case "待確認": return .orange
        case "已核准": return .green
        case "已完成": return .blue
        case "已駁回": return .red
        default: return .gray
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
            PurchaseRequest(title: "電子血壓計（腕式）", category: "醫療用品",
                            description: "需要一組腕式血壓計，方便每日量測",
                            estimatedCost: 1280,
                            status: "待確認", createdAt: Date().addingTimeInterval(-3600),
                            requester: "Rita Santos",
                            notes: "奶奶最近血壓帶有漏氣現象，本的血壓計較腕式比比方便，適合居家日常監測，已來在藥局被認適合格醫療器材。"),
            PurchaseRequest(title: "購買優格和香蕉", category: "食品",
                            description: "爺爺喜歡的零食，一週份量",
                            estimatedCost: nil,
                            status: "已核准", createdAt: Date().addingTimeInterval(-86400),
                            requester: "Rita Santos", notes: ""),
        ]
    }
}

// MARK: - AI Message
struct AIMessage: Identifiable {
    let id = UUID()
    var content: String
    var isUser: Bool
    var timestamp: Date

    static var samples: [AIMessage] {
        [
            AIMessage(content: "請分析一下李奶奶過去三天的血壓趨勢。",
                      isUser: true, timestamp: Date().addingTimeInterval(-600)),
            AIMessage(content: "根據過去72小時的數據顯示，李奶奶的血壓呈現小幅波動但總體趨於穩定。收縮壓在 **128-135 mmHg** 之間，舒張壓穩定在 **78-82 mmHg**。\n\n建議：當前狀態良好，請繼續保持低鹽飲食。",
                      isUser: false, timestamp: Date().addingTimeInterval(-550)),
            AIMessage(content: "需要現在調整用藥嗎？",
                      isUser: true, timestamp: Date().addingTimeInterval(-300)),
        ]
    }
}

// MARK: - First Aid Scenario
struct FirstAidScenario: Identifiable {
    let id = UUID()
    var title: String
    var icon: String
    var color: Color
    var steps: [String]

    static var samples: [FirstAidScenario] {
        [
            FirstAidScenario(title: "昏厥", icon: "person.fill.questionmark", color: .red, steps: [
                "保持呼吸道通暢 — 請確保患者在堅固的平面上，輕輕抬起下巴，使頭部後仰。",
                "尋找 AED 設備 — 如果有旁人在場，請立即呼叫其尋找最近的自動體外除顫器 (AED)。",
                "準備胸外按壓 — 雙臂伸直，雙手叠扣，按壓位置在兩乳頭連線中點，按壓深度約 5 厘米。",
            ]),
            FirstAidScenario(title: "胸痛", icon: "heart.fill", color: .red, steps: [
                "立即讓患者坐下或躺下，保持安靜。",
                "撥打 119 急救電話。",
                "若患者有硝化甘油，協助其舌下含服。",
            ]),
            FirstAidScenario(title: "跌倒", icon: "figure.fall", color: .orange, steps: [
                "不要立刻移動患者，評估意識狀態。",
                "檢查是否有明顯骨折或出血。",
                "若有意識但無法站立，撥打 119 並保持患者溫暖。",
            ]),
            FirstAidScenario(title: "呼吸困難", icon: "lungs.fill", color: .blue, steps: [
                "協助患者採坐姿，身體稍微前傾。",
                "鬆開頸部衣物，確保呼吸道通暢。",
                "立即撥打 119。",
            ]),
            FirstAidScenario(title: "嘔吐", icon: "mouth.fill", color: .orange, steps: [
                "讓患者側躺，防止吸入嘔吐物。",
                "保持頭部側向一方。",
                "清潔口腔，提供漱口水。",
            ]),
            FirstAidScenario(title: "出血", icon: "drop.fill", color: .red, steps: [
                "用乾淨的布料直接加壓止血。",
                "若出血不止，持續加壓並抬高傷肢。",
                "嚴重出血請立即撥打 119。",
            ]),
        ]
    }
}
