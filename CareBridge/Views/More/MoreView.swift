import SwiftUI

// MARK: - Navigation Destination Enum
enum MoreDestination: Hashable {
    case medication
    case health
    case todo
    case documents
    case notifications
}

// MARK: - MoreView
struct MoreView: View {
    @Binding var showProfile: Bool
    let userRole: UserRole
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
                LazyVGrid(columns: featureColumns, spacing: usesWideLayout ? 16 : 12) {
                    ForEach(features) { feature in
                        NavigationLink(value: feature.destination) {
                            FeatureCard(item: feature)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, usesWideLayout ? 32 : 16)
                .padding(.top, usesWideLayout ? 16 : 8)
                .frame(maxWidth: usesWideLayout ? 980 : .infinity)
                .frame(maxWidth: .infinity)
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
                    NotificationBellButton { showNotifications = true }
                }
            }
            // MARK: - Push destinations (tab bar stays visible)
            .navigationDestination(for: MoreDestination.self) { dest in
                switch dest {
                case .medication:    MedicationView(userRole: userRole)
                case .health:        HealthMonitorView()
                case .todo:          TodoView(userRole: userRole)
                case .documents:     DocumentsView(userRole: userRole)
                case .notifications: NotificationCenterView()
                }
            }
            .navigationDestination(isPresented: $showNotifications) {
                NotificationCenterView()
            }
        }
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var featureColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: usesWideLayout ? 16 : 12),
            count: usesWideLayout ? 3 : 2
        )
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
        .environment(NotificationStore(service: MockDataService()))
}
