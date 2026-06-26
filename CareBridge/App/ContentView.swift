import SwiftUI

private enum MainTab: Int, CaseIterable, Identifiable, Hashable {
    case home
    case chat
    case careLog
    case spending
    case more
    case medication
    case health
    case calendar
    case todo
    case documents

    var id: Self { self }

    static let iPhoneTabs: [Self] = [
        .home,
        .chat,
        .careLog,
        .spending,
        .more,
    ]

    static let iPadSidebarTabs: [Self] = [
        .home,
        .chat,
        .careLog,
        .spending,
        .medication,
        .health,
        .calendar,
        .todo,
        .documents,
    ]

    var title: LocalizedStringKey {
        switch self {
        case .home:       return "首頁"
        case .chat:       return "聊天"
        case .careLog:    return "日誌"
        case .spending:   return "消費"
        case .more:       return "更多"
        case .medication: return "用藥管理"
        case .health:     return "健康監測"
        case .calendar:   return "行事曆"
        case .todo:       return "代辦事項"
        case .documents:  return "文件管理"
        }
    }

    var systemImage: String {
        switch self {
        case .home:       return "house.fill"
        case .chat:       return "message.fill"
        case .careLog:    return "doc.text.fill"
        case .spending:   return "cart.fill"
        case .more:       return "ellipsis"
        case .medication: return "pills.fill"
        case .health:     return "heart.fill"
        case .calendar:   return "calendar"
        case .todo:       return "checkmark.circle.fill"
        case .documents:  return "folder.fill"
        }
    }
}

struct ContentView: View {
    @Binding var isLoggedIn: Bool
    let userRole: UserRole
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: MainTab = .home
    @State private var showAIAgent = false
    @State private var showSOS = false
    @State private var showProfile = false
    @State private var isInChatDetail = false
    @State private var isInHomeDetail = false
    @State private var previewedPhoto: PhotoPreviewItem?

    var body: some View {
        ZStack {
            if usesSidebarLayout {
                iPadSidebarSurface
                    .allowsHitTesting(previewedPhoto == nil)
            } else {
                iPhoneTabSurface
                    .allowsHitTesting(previewedPhoto == nil)
            }

            if let previewedPhoto {
                PhotoPreviewOverlay(
                    item: previewedPhoto,
                    onDismiss: dismissPhotoPreview
                )
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isInChatDetail)
        .animation(.easeInOut(duration: 0.2), value: isInHomeDetail)
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .onChange(of: selectedTab) { _, newTab in
            if newTab != .chat {
                isInChatDetail = false
            }
            if newTab != .home {
                isInHomeDetail = false
            }
        }
        .onChange(of: usesSidebarLayout) { _, usesSidebarLayout in
            if !usesSidebarLayout && !MainTab.iPhoneTabs.contains(selectedTab) {
                selectedTab = .more
            }
        }
        .sheet(isPresented: $showAIAgent) {
            NavigationStack {
                AIAgentView(isModal: true)
            }
        }
        .sheet(isPresented: $showSOS) {
            NavigationStack { FirstAidView(isModal: true) }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(isLoggedIn: $isLoggedIn, userRole: userRole)
        }
    }

    private var usesSidebarLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var iPhoneTabSurface: some View {
        TabView(selection: $selectedTab) {
            Tab(MainTab.home.title, systemImage: MainTab.home.systemImage, value: MainTab.home) {
                rootView(for: .home)
            }
            Tab(MainTab.chat.title, systemImage: MainTab.chat.systemImage, value: MainTab.chat) {
                rootView(for: .chat)
            }
            Tab(MainTab.careLog.title, systemImage: MainTab.careLog.systemImage, value: MainTab.careLog) {
                rootView(for: .careLog)
            }
            Tab(MainTab.spending.title, systemImage: MainTab.spending.systemImage, value: MainTab.spending) {
                rootView(for: .spending)
            }
            Tab(MainTab.more.title, systemImage: MainTab.more.systemImage, value: MainTab.more) {
                rootView(for: .more)
            }
        }
        .tint(Color.brandTeal)
        .overlay(alignment: .bottomLeading) {
            aiFloatingButton(bottomPadding: 70)
        }
        .overlay(alignment: .bottomTrailing) {
            sosFloatingButton(bottomPadding: 70)
        }
    }

    private var iPadSidebarSurface: some View {
        NavigationSplitView {
            List {
                Section {
                    ForEach(MainTab.iPadSidebarTabs) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Label {
                                Text(tab.title)
                                    .font(.system(size: 16, weight: selectedTab == tab ? .semibold : .regular))
                            } icon: {
                                Image(systemName: tab.systemImage)
                                    .foregroundStyle(selectedTab == tab ? Color.brandTeal : .secondary)
                            }
                            .foregroundStyle(selectedTab == tab ? Color.brandTeal : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedTab == tab ? Color.brandTealLight : Color.clear)
                                .padding(.vertical, 2)
                        )
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("CareBridge")
        } detail: {
            ZStack {
                rootView(for: selectedTab)
                aiFloatingButton(bottomPadding: 28)
                sosFloatingButton(bottomPadding: 28)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Color.brandTeal)
    }

    @ViewBuilder
    private func rootView(for tab: MainTab) -> some View {
        switch tab {
        case .home:
            HomeView(
                showProfile: $showProfile,
                isInHomeDetail: $isInHomeDetail,
                userRole: userRole,
                previewedPhotoID: previewedPhoto?.id,
                onPreviewPhoto: presentPhotoPreview
            )
        case .chat:
            ChatListView(showProfile: $showProfile, isInChatDetail: $isInChatDetail, userRole: userRole)
        case .careLog:
            CareLogView(
                showProfile: $showProfile,
                userRole: userRole,
                previewedPhotoID: previewedPhoto?.id,
                onPreviewPhoto: presentPhotoPreview
            )
        case .spending:
            SpendingView(showProfile: $showProfile, userRole: userRole)
        case .more:
            MoreView(showProfile: $showProfile, userRole: userRole)
        case .medication:
            MedicationView(userRole: userRole)
        case .health:
            HealthMonitorView()
        case .calendar:
            SharedCalendarView()
        case .todo:
            TodoView()
        case .documents:
            DocumentsView()
        }
    }

    @ViewBuilder
    private func aiFloatingButton(bottomPadding: CGFloat) -> some View {
        if !isInChatDetail {
            Button {
                showAIAgent = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.brandTeal)
                        .frame(width: 52, height: 52)
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .padding(.leading, 24)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("CareBridge AI")
        }
    }

    @ViewBuilder
    private func sosFloatingButton(bottomPadding: CGFloat) -> some View {
        // SOS — only on the home tab's root view; hidden when nav is pushed
        // (e.g. medication detail) to avoid colliding with that page's
        // floating "+" button. Mirrors the AI button's 52pt circle position.
        if selectedTab == .home && !isInHomeDetail {
            Button {
                showSOS = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.85, green: 0.15, blue: 0.15))
                        .frame(width: 52, height: 52)
                    Text("SOS")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.trailing, 24)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("SOS Emergency")
        }
    }

    private func presentPhotoPreview(_ item: PhotoPreviewItem) {
        previewedPhoto = item
    }

    private func dismissPhotoPreview() {
        previewedPhoto = nil
    }
}

#Preview {
    ContentView(isLoggedIn: .constant(true), userRole: .family)
        .environment(CareLogStore())
        .environment(TodoStore())
        .environment(CalendarStore())
        .environment(MedicationStore())
}
