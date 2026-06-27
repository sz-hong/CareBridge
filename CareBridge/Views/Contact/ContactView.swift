import SwiftUI

struct ContactView: View {
    @Binding var showProfile: Bool
    @Binding var isInChatDetail: Bool
    let userRole: UserRole

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.floatingActionBottomPadding) private var floatingActionBottomPadding
    @Environment(\.dataService) private var service
    @State private var chatRooms: [ChatRoom] = []
    @State private var navPath = NavigationPath()
    @State private var showNotifications = false
    @State private var showCreateMenu = false
    @State private var activeSheet: ContactSheet?

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    chatSection
                    requestSection
                    Spacer(minLength: 96)
                }
                .padding(.horizontal, usesWideLayout ? 32 : 16)
                .padding(.top, usesWideLayout ? 16 : 8)
                .frame(maxWidth: usesWideLayout ? 780 : .infinity)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color.brandBackground)
            .scrollIndicators(.hidden)
            .navigationTitle("聯絡")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NotificationBellButton { showNotifications = true }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if navPath.isEmpty && userRole == .caregiver {
                    Button {
                        showCreateMenu = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.brandTeal)
                                .frame(width: 52, height: 52)
                                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.trailing, usesWideLayout ? 32 : 20)
                    .padding(.bottom, floatingActionBottomPadding)
                    .accessibilityLabel("新增聯絡事項")
                }
            }
            .confirmationDialog("聯絡事項", isPresented: $showCreateMenu, titleVisibility: .visible) {
                Button("新增採購需求") { activeSheet = .purchase }
                Button("新增請假申請") { activeSheet = .leave }
                Button("取消", role: .cancel) { }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .purchase:
                    AddPurchaseRequestView { _ in
                        activeSheet = nil
                    }
                case .leave:
                    AddLeaveRequestView { _ in
                        activeSheet = nil
                    }
                }
            }
            .navigationDestination(for: ChatRoom.self) { room in
                ChatDetailView(room: room, userRole: userRole)
            }
            .navigationDestination(for: ContactRoute.self) { route in
                switch route {
                case .purchaseRequests:
                    MessageBoardView(userRole: userRole)
                case .leaveRequests:
                    LeaveManagementView(userRole: userRole)
                }
            }
            .navigationDestination(isPresented: $showNotifications) {
                NotificationCenterView()
            }
            .onChange(of: navPath.count) { _, newCount in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isInChatDetail = newCount > 0
                }
            }
            .task {
                chatRooms = (try? await service.fetchChatRooms()) ?? []
            }
        }
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("聊天室")
                .font(.system(size: 17, weight: .bold))

            VStack(spacing: 10) {
                if chatRooms.isEmpty {
                    ContentUnavailableView("沒有更多訊息", systemImage: "message")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    ForEach(chatRooms) { room in
                        ChatRoomRow(room: room) {
                            navPath.append(room)
                        }

                        if room.id != chatRooms.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(.white))
        }
    }

    private var requestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("採購/請假申請")
                .font(.system(size: 17, weight: .bold))

            VStack(spacing: 12) {
                NavigationLink(value: ContactRoute.purchaseRequests) {
                    ContactActionCard(
                        icon: "cart.fill",
                        title: userRole == .caregiver ? "採購需求" : "採購核准",
                        subtitle: userRole == .caregiver ? "新增與追蹤家中用品需求" : "查看並回覆採購申請",
                        color: .orange
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: ContactRoute.leaveRequests) {
                    ContactActionCard(
                        icon: "calendar.badge.clock",
                        title: userRole == .caregiver ? "請假申請" : "請假核准",
                        subtitle: userRole == .caregiver ? "送出請假並通知家屬" : "查看家屬是否能協助照護",
                        color: .blue
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private enum ContactRoute: Hashable {
    case purchaseRequests
    case leaveRequests
}

private enum ContactSheet: Hashable, Identifiable {
    case purchase
    case leave

    var id: Self { self }
}

private struct ContactActionCard: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }
}
