import SwiftUI

/// 登入後尚未加入家庭時顯示此頁面。
/// 加入或建立家庭成功後，userStore.currentUser.family 會有值，
/// CareBridgeApp 自動切換到主 App。
struct FamilySelectionView: View {
    @Binding var isLoggedIn: Bool
    @Binding var userRole: UserRole
    @Environment(UserStore.self) private var userStore
    @State private var showJoinFamily = false
    @State private var showCreateFamily = false

    private var user: UserProfile? { userStore.currentUser }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.brandBackground, Color.brandTealLight.opacity(0.4), Color.brandTealLight],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 48)

                    // 使用者資訊
                    VStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(Color.brandTeal)
                        Text(user?.name ?? "-")
                            .font(.system(size: 20, weight: .bold))
                        Text(user?.email ?? "")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    // 標題
                    VStack(spacing: 6) {
                        Text("設定您的家庭")
                            .font(.system(size: 26, weight: .bold))
                        Text("您尚未加入任何家庭")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }

                    // 選項卡片
                    VStack(spacing: 16) {
                        // 加入家庭
                        optionCard(
                            icon: "envelope.open.fill",
                            iconColor: Color.brandTeal,
                            title: "加入家庭",
                            subtitle: "輸入邀請碼加入現有的家庭群組"
                        ) {
                            showJoinFamily = true
                        }

                        // 建立家庭（僅 family_member）
                        if user?.role == .family || user?.role == nil {
                            optionCard(
                                icon: "house.badge.plus",
                                iconColor: .orange,
                                title: "建立新家庭",
                                subtitle: "建立家庭群組並成為主要家屬"
                            ) {
                                showCreateFamily = true
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // 登出
                    Button {
                        isLoggedIn = false
                    } label: {
                        Text("登出 Logout")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 40)
                }
            }
            .scrollIndicators(.hidden)
        }
        .fullScreenCover(isPresented: $showJoinFamily) {
            // 加入成功 → userStore.currentUser.family 有值 → CareBridgeApp 切到主 App
            JoinFamilyView(isLoggedIn: $isLoggedIn, userRole: $userRole)
        }
        .sheet(isPresented: $showCreateFamily) {
            CreateFamilyView(userRole: $userRole)
        }
    }

    private func optionCard(icon: String, iconColor: Color, title: String,
                            subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(iconColor)
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.white.opacity(0.88))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    FamilySelectionView(isLoggedIn: .constant(true), userRole: .constant(.family))
        .environment(UserStore())
}
