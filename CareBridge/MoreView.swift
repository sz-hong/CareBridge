import SwiftUI

// MARK: - Navigation Destination Enum
enum MoreDestination: Hashable {
    case medication
    case health
    case calendar
    case todo
    case documents
    case leave
    case messageboard
    case ai
    case firstaid
    case notifications
}

// MARK: - MoreView
struct MoreView: View {
    @Binding var showProfile: Bool

    struct FeatureItem {
        let title: String
        let subtitle: String
        let icon: String
        let color: Color
        let destination: MoreDestination?   // nil = SOS (sheet)
        let isSOS: Bool
    }

    private let features: [FeatureItem] = [
        FeatureItem(title: "用藥管理",  subtitle: "藥物清單與提醒",
                    icon: "pills.fill",                  color: .brandTeal,
                    destination: .medication,             isSOS: false),
        FeatureItem(title: "健康監測",  subtitle: "心率·血氧·血壓",
                    icon: "heart.fill",                  color: .red,
                    destination: .health,                 isSOS: false),
        FeatureItem(title: "行事曆",    subtitle: "共享行程管理",
                    icon: "calendar",                    color: .blue,
                    destination: .calendar,               isSOS: false),
        FeatureItem(title: "代辦事項",  subtitle: "指派與追蹤",
                    icon: "checkmark.circle.fill",       color: .orange,
                    destination: .todo,                   isSOS: false),
        FeatureItem(title: "文件管理",  subtitle: "保險·醫療·證件",
                    icon: "folder.fill",                 color: .purple,
                    destination: .documents,              isSOS: false),
        FeatureItem(title: "請假管理",  subtitle: "申請與審核",
                    icon: "calendar.badge.exclamationmark", color: .orange,
                    destination: .leave,                  isSOS: false),
        FeatureItem(title: "採購需求",  subtitle: "留言板",
                    icon: "cart.fill",                   color: .green,
                    destination: .messageboard,           isSOS: false),
        FeatureItem(title: "AI 智慧助理", subtitle: "照護分析·報告",
                    icon: "sparkles",                    color: Color(red: 0.4, green: 0.2, blue: 0.8),
                    destination: .ai,                     isSOS: false),
        FeatureItem(title: "急救小幫手", subtitle: "緊急指引·RAG",
                    icon: "cross.circle.fill",           color: .red,
                    destination: .firstaid,               isSOS: false),
        FeatureItem(title: "SOS 緊急呼叫", subtitle: "一鍵緊急求助",
                    icon: "sos",                         color: .red,
                    destination: nil,                     isSOS: true),
        FeatureItem(title: "通知中心",  subtitle: "所有系統通知",
                    icon: "bell.fill",                   color: .brandTeal,
                    destination: .notifications,          isSOS: false),
    ]

    @State private var showSOS = false
    @State private var showNotifications = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(features, id: \.title) { feature in
                        if let dest = feature.destination {
                            NavigationLink(value: dest) {
                                FeatureCard(item: feature)
                            }
                            .buttonStyle(.plain)
                        } else {
                            // SOS — modal sheet
                            Button { showSOS = true } label: {
                                FeatureCard(item: feature)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer(minLength: 20)
            }
            .background(Color.brandBackground)
            .navigationTitle("更多")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showProfile = true } label: {
                        HStack(spacing: 0) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color.brandTeal)
                            Text("CareBridge")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showNotifications = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.brandTeal)
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 2, y: -2)
                            }
                        }
                        Button { } label: {
                            Image(systemName: "globe")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandTeal)
                        }
                    }
                }
            }
            // MARK: - Push destinations (tab bar stays visible)
            .navigationDestination(for: MoreDestination.self) { dest in
                switch dest {
                case .medication:   MedicationView()
                case .health:       HealthMonitorView()
                case .calendar:     SharedCalendarView()
                case .todo:         TodoView()
                case .documents:    DocumentsView()
                case .leave:        LeaveManagementView()
                case .messageboard: MessageBoardView()
                case .ai:           AIAgentView()
                case .firstaid:     FirstAidView()
                case .notifications: NotificationCenterView()
                }
            }
            .navigationDestination(isPresented: $showNotifications) {
                NotificationCenterView()
            }
        }
        // SOS is still a full-screen modal
        .sheet(isPresented: $showSOS) {
            SOSView()
        }
    }
}

// MARK: - Feature Card
struct FeatureCard: View {
    let item: MoreView.FeatureItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(item.color.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: item.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(item.color)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 130)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }
}

#Preview {
    MoreView(showProfile: .constant(false))
}
