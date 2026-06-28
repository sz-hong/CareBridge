import SwiftUI

/// 全 App 共享的通知狀態來源。鈴鐺的未讀紅點與通知中心都讀這裡，
/// 所以標記已讀後紅點會即時消失（不再永遠亮著）。
@Observable
final class NotificationStore {
    private let service: DataService
    var notifications: [AppNotification] = []

    var unreadCount: Int { notifications.reduce(0) { $0 + ($1.isRead ? 0 : 1) } }

    init(service: DataService) { self.service = service }

    func refresh() async {
        let fetched = try? await service.fetchNotifications()
        await MainActor.run {
            if let fetched { notifications = fetched }
        }
    }

    func markRead(_ id: String) {
        guard let i = notifications.firstIndex(where: { $0.id == id }),
              !notifications[i].isRead else { return }
        notifications[i].isRead = true
        Task { try? await service.markNotificationRead(id: id) }
    }

    func markAllRead() {
        guard unreadCount > 0 else { return }
        for i in notifications.indices where !notifications[i].isRead {
            notifications[i].isRead = true
        }
        Task { try? await service.markAllNotificationsRead() }
    }

    func remove(_ id: String) {
        notifications.removeAll { $0.id == id }
    }
}

struct NotificationCenterView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(NotificationStore.self) private var store
    @State private var showUnreadOnly = false

    var displayedNotifications: [AppNotification] {
        showUnreadOnly ? store.notifications.filter { !$0.isRead } : store.notifications
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header controls
            HStack {
                if store.unreadCount > 0 {
                    Text("\(store.unreadCount) 則未讀")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("僅未讀", isOn: $showUnreadOnly)
                    .font(.system(size: 14))
                    .toggleStyle(.button)
                    .tint(Color.brandTeal)

                Button {
                    withAnimation { store.markAllRead() }
                } label: {
                    Text("全部已讀")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.brandTeal)
                }
                .disabled(store.unreadCount == 0)
            }
            .padding(.horizontal, usesWideLayout ? 32 : 16)
            .padding(.vertical, 8)
            .frame(maxWidth: usesWideLayout ? 900 : .infinity)

            Divider()

            if displayedNotifications.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "bell.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("沒有通知")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: usesWideLayout ? 900 : .infinity)
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(displayedNotifications) { notification in
                        NotificationRow(notification: notification)
                            .listRowBackground(notification.isRead ? Color.clear : Color.brandTealLight.opacity(0.3))
                            .swipeActions(edge: .leading) {
                                Button {
                                    withAnimation { store.markRead(notification.id) }
                                } label: {
                                    Label("標記已讀", systemImage: "checkmark")
                                }
                                .tint(Color.brandTeal)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation { store.remove(notification.id) }
                                } label: {
                                    Label("刪除", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .frame(maxWidth: usesWideLayout ? 900 : .infinity)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.brandBackground)
        .navigationTitle("通知中心")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.refresh() }
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }
}

// MARK: - Notification Bell (toolbar button with live unread dot)

/// 共用的鈴鐺按鈕：只有真的有未讀時才顯示紅點，取代各頁原本「永遠亮」的寫死紅點。
struct NotificationBellButton: View {
    enum ButtonStyle {
        case toolbar
        case prominent
    }

    @Environment(NotificationStore.self) private var store
    var style: ButtonStyle = .toolbar
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            store.unreadCount > 0 ? "通知，\(store.unreadCount) 則未讀" : "通知"
        )
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .toolbar:
            bellGlyph
        case .prominent:
            ZStack {
                Circle()
                    .fill(.white.opacity(0.92))
                    .frame(width: 52, height: 52)
                    .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
                bellGlyph
            }
        }
    }

    private var bellGlyph: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "bell.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.brandTeal)
            if store.unreadCount > 0 {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .offset(x: 2, y: -2)
            }
        }
    }
}

// MARK: - Notification Row
struct NotificationRow: View {
    let notification: AppNotification
    @Environment(LocaleStore.self) private var localeStore

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(notification.category.color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: notification.category.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(notification.category.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(notification.displayTitle(language: localeStore.code))
                        .font(.system(size: 15, weight: notification.isRead ? .regular : .semibold))
                    Spacer()
                    if !notification.isRead {
                        Circle()
                            .fill(Color.brandTeal)
                            .frame(width: 8, height: 8)
                    }
                }
                Text(notification.displayBody(language: localeStore.code))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(relativeTimestampText)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }

    private var relativeTimestampText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = localeStore.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: notification.timestamp, relativeTo: Date())
    }
}

#Preview {
    NavigationStack {
        NotificationCenterView()
    }
    .environment(NotificationStore(service: MockDataService()))
    .environment(LocaleStore())
}
