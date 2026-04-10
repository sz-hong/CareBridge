import SwiftUI

struct ProfileView: View {
    @Binding var isLoggedIn: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                // Avatar + Name header
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.brandTeal)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hank Chen")
                                .font(.system(size: 20, weight: .bold))
                            Text("hank@carebridge.com")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                            Text("主要照護者")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.brandTeal))
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Personal info
                Section("個人資訊") {
                    profileRow(icon: "person.text.rectangle", label: "姓名", value: "Hank Chen")
                    profileRow(icon: "phone.fill", label: "電話", value: "+886 912-345-678")
                    profileRow(icon: "envelope.fill", label: "電子郵件", value: "hank@carebridge.com")
                    profileRow(icon: "birthday.cake.fill", label: "生日", value: "1990/05/15")
                }

                // Family info
                Section("家庭資訊") {
                    profileRow(icon: "house.fill", label: "家庭名稱", value: "Chen Family")
                    profileRow(icon: "person.3.fill", label: "成員數量", value: "4 位成員")
                    profileRow(icon: "shield.checkered", label: "角色", value: "主要照護者")
                }

                // Settings
                Section("設定") {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(Color.brandTeal)
                            .frame(width: 24)
                        Text("通知設定")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(Color.brandTeal)
                            .frame(width: 24)
                        Text("隱私與安全")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .foregroundStyle(Color.brandTeal)
                            .frame(width: 24)
                        Text("語言")
                        Spacer()
                        Text("繁體中文")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                // Logout
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("登出")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("個人資料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                }
            }
            .alert("確定要登出嗎？", isPresented: $showLogoutConfirm) {
                Button("取消", role: .cancel) { }
                Button("登出", role: .destructive) {
                    isLoggedIn = false
                }
            } message: {
                Text("登出後需要重新登入才能使用 CareBridge。")
            }
        }
    }

    private func profileRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.brandTeal)
                .frame(width: 24)
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ProfileView(isLoggedIn: .constant(true))
}
