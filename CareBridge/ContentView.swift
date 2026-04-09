import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("首頁", systemImage: "house.fill", value: 0) {
                HomeView()
            }
            Tab("聊天", systemImage: "message.fill", value: 1) {
                ChatListView()
            }
            Tab("日誌", systemImage: "doc.text.fill", value: 2) {
                CareLogView()
            }
            Tab("消費", systemImage: "cart.fill", value: 3) {
                SpendingView()
            }
            Tab("更多", systemImage: "ellipsis", value: 4) {
                MoreView()
            }
        }
        .tint(Color(red: 0.0, green: 0.50, blue: 0.55))
    }
}

#Preview {
    ContentView()
}
