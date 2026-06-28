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
                VStack(spacing: 18) {
                    RootPageHeader(horizontalPadding: usesWideLayout ? 32 : 16) {
                        showNotifications = true
                    } title: {
                        Text("聯絡")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: usesWideLayout ? 780 : .infinity)
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 18) {
                        chatSection
                        requestSection
                        Spacer(minLength: 96)
                    }
                    .padding(.horizontal, usesWideLayout ? 32 : 16)
                    .frame(maxWidth: usesWideLayout ? 780 : .infinity)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .padding(.top, 4)
            }
            .background(Color.brandBackground)
            .scrollIndicators(.hidden)
            .overlay(alignment: .bottomTrailing) {
                if navPath.isEmpty && userRole == .caregiver {
                    ZStack(alignment: .bottomTrailing) {
                        if showCreateMenu {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    showCreateMenu = false
                                }
                            } label: {
                                Color.clear
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        if showCreateMenu {
                            ContactCreateMenu(
                                onPurchase: {
                                    showCreateMenu = false
                                    activeSheet = .purchase
                                },
                                onLeave: {
                                    showCreateMenu = false
                                    activeSheet = .leave
                                }
                            )
                            .padding(.trailing, usesWideLayout ? 32 : 24)
                            .padding(.bottom, floatingActionBottomPadding + 66)
                            .transition(
                                .scale(scale: 0.96, anchor: .bottomTrailing)
                                    .combined(with: .opacity)
                            )
                        }

                        Button {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                                showCreateMenu.toggle()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.brandTeal)
                                    .frame(width: 52, height: 52)
                                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                                Image(systemName: "plus")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                                    .rotationEffect(.degrees(showCreateMenu ? 45 : 0))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, usesWideLayout ? 32 : 24)
                        .padding(.bottom, floatingActionBottomPadding)
                        .accessibilityLabel("新增聯絡事項")
                    }
                }
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

private struct ContactCreateMenu: View {
    let onPurchase: () -> Void
    let onLeave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("聯絡事項")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, 18)
                .padding(.bottom, 12)

            VStack(spacing: 10) {
                menuButton("新增採購需求", action: onPurchase)
                menuButton("新增請假申請", action: onLeave)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
        .overlay(alignment: .bottomTrailing) {
            ContactMenuArrow()
                .fill(.ultraThinMaterial)
                .frame(width: 26, height: 14)
                .offset(x: -13, y: 12)
        }
    }

    private func menuButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.brandTeal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(Color(.systemGray4).opacity(0.55))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ContactMenuArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
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
