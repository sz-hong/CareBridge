import SwiftUI

// MARK: - Navigation Destination Enum
enum MoreDestination: Hashable {
    case medication
    case health
    case calendar
    case todo
    case documents
    case notifications
}

// MARK: - MoreView
struct MoreView: View {
    @Binding var showProfile: Bool
    let userRole: UserRole

    struct FeatureItem: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
        let icon: String
        let color: Color
        let destination: MoreDestination
    }

    private let features: [FeatureItem] = [
        FeatureItem(title: "用藥管理", subtitle: "藥物清單與提醒",
                    icon: "pills.fill",            color: .brandTeal,
                    destination: .medication),
        FeatureItem(title: "健康監測", subtitle: "心率·血氧·血壓",
                    icon: "heart.fill",            color: .red,
                    destination: .health),
        FeatureItem(title: "行事曆",   subtitle: "共享行程管理",
                    icon: "calendar",              color: .blue,
                    destination: .calendar),
        FeatureItem(title: "代辦事項", subtitle: "指派與追蹤",
                    icon: "checkmark.circle.fill", color: .orange,
                    destination: .todo),
        FeatureItem(title: "文件管理", subtitle: "保險·醫療·證件",
                    icon: "folder.fill",           color: .purple,
                    destination: .documents),
    ]

    @State private var showNotifications = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(features) { feature in
                        NavigationLink(value: feature.destination) {
                            FeatureCard(item: feature)
                        }
                        .buttonStyle(.plain)
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
                case .medication:    MedicationView(userRole: userRole)
                case .health:        HealthMonitorView()
                case .calendar:      SharedCalendarView()
                case .todo:          TodoView()
                case .documents:     DocumentsView()
                case .notifications: NotificationCenterView()
                }
            }
            .navigationDestination(isPresented: $showNotifications) {
                NotificationCenterView()
            }
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
    MoreView(showProfile: .constant(false), userRole: .family)
        .environment(CareLogStore())
        .environment(TodoStore())
        .environment(CalendarStore())
        .environment(MedicationStore())
}
