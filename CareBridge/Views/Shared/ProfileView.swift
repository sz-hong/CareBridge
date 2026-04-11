import SwiftUI

struct ProfileView: View {
    @Binding var isLoggedIn: Bool
    let userRole: UserRole
    @Environment(\.dismiss) private var dismiss
    @State private var showLogoutConfirm = false
    @State private var showEditProfile = false
    @State private var showFamilyMembers = false
    @State private var showNotificationPrefs = false

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
                            Text(userRole == .caregiver ? "看護" : "家屬")
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
                    Button {
                        showEditProfile = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundStyle(Color.brandTeal)
                                .frame(width: 24)
                            Text("編輯個人資料")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                // Family info
                Section("家庭資訊") {
                    profileRow(icon: "house.fill", label: "家庭名稱", value: "Chen Family")
                    profileRow(icon: "shield.checkered", label: "角色", value: userRole == .caregiver ? "看護" : "家屬")
                    Button {
                        showFamilyMembers = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.3.fill")
                                .foregroundStyle(Color.brandTeal)
                                .frame(width: 24)
                            Text("查看家庭成員")
                            Spacer()
                            Text("4 位")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                // Settings
                Section("設定") {
                    Button {
                        showNotificationPrefs = true
                    } label: {
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
                    }
                    .foregroundStyle(.primary)
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
            .sheet(isPresented: $showEditProfile) {
                EditProfileView()
            }
            .sheet(isPresented: $showFamilyMembers) {
                FamilyMembersView(userRole: userRole)
            }
            .sheet(isPresented: $showNotificationPrefs) {
                NotificationPreferencesView()
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

// MARK: - Edit Profile View
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Hank Chen"
    @State private var phone = "+886 912-345-678"
    @State private var birthday = Calendar.current.date(from: DateComponents(year: 1990, month: 5, day: 15)) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("個人資訊") {
                    LabeledContent("姓名") {
                        TextField("姓名", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("電話") {
                        TextField("電話號碼", text: $phone)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.phonePad)
                    }
                    DatePicker("生日", selection: $birthday, displayedComponents: .date)
                }

                Section("頭像") {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(Color.brandTeal)
                            Button("更換頭像") { }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.brandTeal)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    Button(role: .destructive) { } label: {
                        HStack {
                            Spacer()
                            Text("刪除帳號")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("編輯個人資料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { dismiss() }
                        .bold()
                        .foregroundStyle(Color.brandTeal)
                }
            }
        }
    }
}

// MARK: - Family Members View
struct FamilyMembersView: View {
    @Environment(\.dismiss) private var dismiss
    let userRole: UserRole

    private let members: [(name: String, role: String, relation: String, isOnline: Bool)] = [
        ("林小明", "家屬", "兒子", true),
        ("林大華", "家屬", "父親", false),
        ("林美華", "家屬", "母親", true),
        ("Maria Santos", "看護", "看護", true),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("成員列表（\(members.count) 位）") {
                    ForEach(members, id: \.name) { member in
                        HStack(spacing: 14) {
                            ZStack(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(Color.brandTealLight)
                                    .frame(width: 48, height: 48)
                                Image(systemName: member.role == "看護" ? "cross.case.fill" : "person.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.brandTeal)
                                Circle()
                                    .fill(member.isOnline ? Color.green : Color.gray)
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(member.name)
                                    .font(.system(size: 15, weight: .semibold))
                                HStack(spacing: 6) {
                                    Text(member.relation)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                    Text("·")
                                        .foregroundStyle(.secondary)
                                    Text(member.role)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(member.role == "看護" ? Color.brandTeal : .orange)
                                }
                            }

                            Spacer()

                            if member.isOnline {
                                Text("在線")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if userRole == .family {
                    Section {
                        HStack {
                            Image(systemName: "qrcode")
                                .foregroundStyle(Color.brandTeal)
                                .frame(width: 24)
                            Text("邀請碼：AB-1234")
                                .font(.system(size: 15, weight: .medium))
                            Spacer()
                            Button("複製") { }
                                .font(.system(size: 14))
                                .foregroundStyle(Color.brandTeal)
                        }
                        Button {
                            // Regenerate code
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                Text("重新產生邀請碼")
                            }
                            .foregroundStyle(Color.brandTeal)
                        }
                    } header: {
                        Text("邀請新成員")
                    }
                }
            }
            .navigationTitle("家庭成員")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.brandTeal)
                }
            }
        }
    }
}

// MARK: - Notification Preferences View
struct NotificationPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var medicationReminder = true
    @State private var careLogUpdate = true
    @State private var sosAlert = true
    @State private var todoAssigned = true
    @State private var calendarEvent = true
    @State private var chatMessage = true
    @State private var leaveRequest = false
    @State private var purchaseRequest = false

    var body: some View {
        NavigationStack {
            Form {
                Section("照護通知") {
                    Toggle("用藥提醒", isOn: $medicationReminder)
                    Toggle("照護日誌更新", isOn: $careLogUpdate)
                    Toggle("SOS 緊急警報", isOn: $sosAlert)
                }

                Section("任務與行程") {
                    Toggle("待辦事項指派", isOn: $todoAssigned)
                    Toggle("行事曆提醒", isOn: $calendarEvent)
                }

                Section("溝通") {
                    Toggle("新聊天訊息", isOn: $chatMessage)
                    Toggle("請假申請", isOn: $leaveRequest)
                    Toggle("採購需求", isOn: $purchaseRequest)
                }

                Section {
                    Text("通知將透過 APNs 推播送達。您可以隨時在 iOS 設定中管理推播權限。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color.brandTeal)
            .navigationTitle("通知設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.brandTeal)
                }
            }
        }
    }
}

#Preview {
    ProfileView(isLoggedIn: .constant(true), userRole: .family)
}
