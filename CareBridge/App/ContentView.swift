import SwiftUI

struct ContentView: View {
    @Binding var isLoggedIn: Bool
    let userRole: UserRole
    @State private var selectedTab = 0
    @State private var showAIAgent = false
    @State private var showSOS = false
    @State private var showProfile = false
    @State private var isInChatDetail = false
    @State private var isInHomeDetail = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("首頁", systemImage: "house.fill", value: 0) {
                HomeView(showProfile: $showProfile, isInHomeDetail: $isInHomeDetail, userRole: userRole)
            }
            Tab("聊天", systemImage: "message.fill", value: 1) {
                ChatListView(showProfile: $showProfile, isInChatDetail: $isInChatDetail, userRole: userRole)
            }
            Tab("日誌", systemImage: "doc.text.fill", value: 2) {
                CareLogView(showProfile: $showProfile, userRole: userRole)
            }
            Tab("消費", systemImage: "cart.fill", value: 3) {
                SpendingView(showProfile: $showProfile, userRole: userRole)
            }
            Tab("更多", systemImage: "ellipsis", value: 4) {
                MoreView(showProfile: $showProfile, userRole: userRole)
            }
        }
        .tint(Color(red: 0.0, green: 0.50, blue: 0.55))
        .overlay(alignment: .bottomLeading) {
            if !isInChatDetail {
                Button {
                    showAIAgent = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.0, green: 0.50, blue: 0.55))
                            .frame(width: 52, height: 52)
                        Image(systemName: "sparkles")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.leading, 20)
                .padding(.bottom, 70)
                .transition(.scale.combined(with: .opacity))
            }
        }
        // SOS — only on the home tab's root view; hidden when nav is pushed
        // (e.g. medication detail) to avoid colliding with that page's
        // floating "+" button. Mirrors the AI button's 52pt circle position.
        .overlay(alignment: .bottomTrailing) {
            if selectedTab == 0 && !isInHomeDetail {
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
                .padding(.trailing, 20)
                .padding(.bottom, 70)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("SOS Emergency")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isInChatDetail)
        .animation(.easeInOut(duration: 0.2), value: isInHomeDetail)
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
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
}

#Preview {
    ContentView(isLoggedIn: .constant(true), userRole: .family)
        .environment(CareLogStore())
        .environment(TodoStore())
        .environment(CalendarStore())
        .environment(MedicationStore())
}
