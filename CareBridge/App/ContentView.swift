import SwiftUI

struct ContentView: View {
    @Binding var isLoggedIn: Bool
    let userRole: UserRole
    @State private var selectedTab = 0
    @State private var showAIAgent = false
    @State private var showProfile = false
    @State private var isInChatDetail = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("首頁", systemImage: "house.fill", value: 0) {
                HomeView(showProfile: $showProfile, userRole: userRole)
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
        .animation(.easeInOut(duration: 0.2), value: isInChatDetail)
        .sheet(isPresented: $showAIAgent) {
            NavigationStack {
                AIAgentView(isModal: true)
            }
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
