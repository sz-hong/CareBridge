import SwiftUI

struct NotificationCenterView: View {
    @Environment(\.dataService) private var service
    @State private var notifications: [AppNotification] = []
    @State private var showUnreadOnly = false

    var displayedNotifications: [AppNotification] {
        showUnreadOnly ? notifications.filter { !$0.isRead } : notifications
    }

    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header controls
            HStack {
                if unreadCount > 0 {
                    Text("\(unreadCount) 則未讀")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("僅未讀", isOn: $showUnreadOnly)
                    .font(.system(size: 14))
                    .toggleStyle(.button)
                    .tint(Color.brandTeal)

                Button {
                    markAllAsRead()
                } label: {
                    Text("全部已讀")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.brandTeal)
                }
                .disabled(unreadCount == 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

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
            } else {
                List {
                    ForEach(displayedNotifications) { notification in
                        NotificationRow(notification: notification)
                            .listRowBackground(notification.isRead ? Color.clear : Color.brandTealLight.opacity(0.3))
                            .swipeActions(edge: .leading) {
                                Button {
                                    markAsRead(notification)
                                } label: {
                                    Label("標記已讀", systemImage: "checkmark")
                                }
                                .tint(Color.brandTeal)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteNotification(notification)
                                } label: {
                                    Label("刪除", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color.brandBackground)
        .navigationTitle("通知中心")
        .navigationBarTitleDisplayMode(.large)
        .task {
            notifications = (try? await service.fetchNotifications()) ?? []
        }
    }

    private func markAsRead(_ notification: AppNotification) {
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            withAnimation { notifications[index].isRead = true }
            Task { try? await service.markNotificationRead(id: notification.id) }
        }
    }

    private func markAllAsRead() {
        withAnimation {
            for i in notifications.indices {
                notifications[i].isRead = true
            }
        }
        Task { try? await service.markAllNotificationsRead() }
    }

    private func deleteNotification(_ notification: AppNotification) {
        withAnimation {
            notifications.removeAll { $0.id == notification.id }
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
                Text(notification.timestamp.formatted(.relative(presentation: .named)))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        NotificationCenterView()
    }
}
