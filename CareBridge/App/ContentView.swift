import SwiftUI

private enum MainTab: Int, CaseIterable, Identifiable, Hashable {
    case home
    case careLog
    case contact
    case management
    case settings
    case medication
    case health
    case todo
    case documents

    var id: Self { self }

    static let iPhoneTabs: [Self] = [
        .home,
        .careLog,
        .contact,
        .management,
        .settings,
    ]

    static let iPadSidebarTabs: [Self] = [
        .home,
        .careLog,
        .contact,
        .management,
        .medication,
        .health,
        .todo,
        .documents,
        .settings,
    ]

    var title: LocalizedStringKey {
        switch self {
        case .home:       return "首頁"
        case .careLog:    return "日誌"
        case .contact:    return "聯絡"
        case .management: return "管理"
        case .settings:   return "個人/設定"
        case .medication: return "用藥管理"
        case .health:     return "健康監測"
        case .todo:       return "代辦事項"
        case .documents:  return "文件管理"
        }
    }

    var systemImage: String {
        switch self {
        case .home:       return "house.fill"
        case .careLog:    return "doc.text.fill"
        case .contact:    return "message.fill"
        case .management: return "seal.fill"
        case .settings:   return "person.crop.circle.fill"
        case .medication: return "pills.fill"
        case .health:     return "heart.fill"
        case .todo:       return "checkmark.circle.fill"
        case .documents:  return "folder.fill"
        }
    }

    var bottomSystemImage: String {
        switch self {
        case .home:       return "house.fill"
        case .careLog:    return "doc.text.fill"
        case .contact:    return "bubble.left.and.bubble.right.fill"
        case .management: return "briefcase.fill"
        case .settings:   return "gearshape.fill"
        default:          return systemImage
        }
    }
}

private enum FloatingActionLayout {
    /// Overlay buttons attached to the whole phone TabView (AI / SOS).
    /// This coordinate space includes the system tab bar, so the value must
    /// keep the button just above the native bar.
    static let phoneGlobalBottom: CGFloat = 58

    /// Page-owned floating buttons (`+`, scan, edit) live inside each tab's
    /// content area, which already ends above the native tab bar. Using the
    /// global value here pushes those buttons too high and makes them look
    /// misaligned with the AI button.
    static let phoneContentBottom: CGFloat = 12

    static let pushedDetailBottom: CGFloat = 20
    static let padBottom: CGFloat = 28
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
            if newTab != .contact {
                isInChatDetail = false
            }
            if newTab != .home {
                isInHomeDetail = false
            }
        }
        .onChange(of: usesSidebarLayout) { _, usesSidebarLayout in
            if !usesSidebarLayout && !MainTab.iPhoneTabs.contains(selectedTab) {
                selectedTab = .management
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
            Tab(value: MainTab.home) {
                iPhoneTabRoot(for: .home)
            } label: {
                tabIcon(for: .home)
            }
            Tab(value: MainTab.careLog) {
                iPhoneTabRoot(for: .careLog)
            } label: {
                tabIcon(for: .careLog)
            }
            Tab(value: MainTab.contact) {
                iPhoneTabRoot(for: .contact)
            } label: {
                tabIcon(for: .contact)
            }
            Tab(value: MainTab.management) {
                iPhoneTabRoot(for: .management)
            } label: {
                tabIcon(for: .management)
            }
            Tab(value: MainTab.settings) {
                iPhoneTabRoot(for: .settings)
            } label: {
                tabIcon(for: .settings)
            }
        }
        .toolbarVisibility(isInChatDetail ? .hidden : .visible, for: .tabBar)
        .tint(Color.brandTeal)
        .overlay(alignment: .bottomLeading) {
            aiFloatingButton(
                bottomPadding: isInChatDetail
                    ? FloatingActionLayout.pushedDetailBottom
                    : FloatingActionLayout.phoneGlobalBottom
            )
        }
        .overlay(alignment: .bottomTrailing) {
            sosFloatingButton(
                bottomPadding: isInChatDetail
                    ? FloatingActionLayout.pushedDetailBottom
                    : FloatingActionLayout.phoneGlobalBottom
            )
        }
    }

    private func iPhoneTabRoot(for tab: MainTab) -> some View {
        rootView(for: tab)
            .environment(
                \.floatingActionBottomPadding,
                isInChatDetail
                    ? FloatingActionLayout.pushedDetailBottom
                    : FloatingActionLayout.phoneContentBottom
            )
    }

    private func tabIcon(for tab: MainTab) -> some View {
        Image(systemName: tab.bottomSystemImage)
            .accessibilityLabel(tab.title)
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
                    .environment(
                        \.floatingActionBottomPadding,
                        FloatingActionLayout.padBottom
                    )
                aiFloatingButton(bottomPadding: FloatingActionLayout.padBottom)
                sosFloatingButton(bottomPadding: FloatingActionLayout.padBottom)
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
        case .careLog:
            CareLogView(
                showProfile: $showProfile,
                userRole: userRole,
                previewedPhotoID: previewedPhoto?.id,
                onPreviewPhoto: presentPhotoPreview
            )
        case .contact:
            ContactView(showProfile: $showProfile, isInChatDetail: $isInChatDetail, userRole: userRole)
        case .management:
            ManagementView(showProfile: $showProfile, userRole: userRole)
        case .settings:
            ProfileView(isLoggedIn: $isLoggedIn, userRole: userRole, isModal: false)
        case .medication:
            MedicationView(userRole: userRole)
        case .health:
            HealthMonitorView()
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
        .environment(TodaySummaryStore())
}
