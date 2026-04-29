import SwiftUI

struct ProfileView: View {
    @Binding var isLoggedIn: Bool
    let userRole: UserRole
    @Environment(\.dismiss) private var dismiss
    @Environment(UserStore.self) private var userStore
    @Environment(\.dataService) private var service
    @State private var showLogoutConfirm = false
    @State private var showEditProfile = false
    @State private var showFamilyMembers = false
    @State private var showNotificationPrefs = false
    @State private var inviteCodeCopied = false

    private var user: UserProfile? { userStore.currentUser }

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
                            Text(user?.name ?? "-")
                                .font(.system(size: 20, weight: .bold))
                            Text(user?.email ?? "-")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                            Text((user?.role ?? userRole).displayName)
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
                    profileRow(icon: "person.text.rectangle", label: "姓名", value: user?.name ?? "-")
                    profileRow(icon: "phone.fill", label: "電話", value: user?.phone ?? "-")
                    profileRow(icon: "envelope.fill", label: "電子郵件", value: user?.email ?? "-")
                    profileRow(icon: "birthday.cake.fill", label: "生日", value: user?.birthday ?? "-")
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
                    profileRow(icon: "house.fill", label: "家庭名稱", value: user?.familyName.isEmpty == false ? user!.familyName : "-")
                    profileRow(icon: "shield.checkered", label: "角色", value: (user?.role ?? userRole).displayName)
                    if let code = user?.familyInviteCode, !code.isEmpty {
                        Button {
                            UIPasteboard.general.string = code
                            inviteCodeCopied = true
                        } label: {
                            profileRow(icon: "qrcode", label: "家庭邀請碼",
                                       value: inviteCodeCopied ? "已複製" : code)
                        }
                        .foregroundStyle(.primary)
                    }
                    Button {
                        showFamilyMembers = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.3.fill")
                                .foregroundStyle(Color.brandTeal)
                                .frame(width: 24)
                            Text("查看家庭成員")
                            Spacer()
                            Text("\(userStore.familyMembers.count) 位")
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
                    Menu {
                        ForEach(SupportedLanguage.all, id: \.code) { lang in
                            Button {
                                Task { await updateLanguage(lang.code) }
                            } label: {
                                if lang.code == (user?.language ?? "zh-TW") {
                                    Label(lang.displayName, systemImage: "checkmark")
                                } else {
                                    Text(lang.displayName)
                                }
                            }
                        }
                    } label: {
                        profileRow(icon: "globe", label: "語言",
                                   value: SupportedLanguage.displayName(for: user?.language))
                    }
                    .foregroundStyle(.primary)
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

    private func updateLanguage(_ code: String) async {
        guard var profile = userStore.currentUser, profile.language != code else { return }
        profile.language = code
        if let updated = try? await service.updateProfile(profile) {
            userStore.currentUser = updated
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
    @Environment(UserStore.self) private var userStore
    @Environment(\.dataService) private var service
    @State private var name = ""
    @State private var phone = ""
    @State private var isSaving = false

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
                }

                Section("頭像") {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(Color.brandTeal)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("編輯個人資料")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                name  = userStore.currentUser?.name  ?? ""
                phone = userStore.currentUser?.phone ?? ""
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") {
                        Task {
                            guard var profile = userStore.currentUser else { return }
                            profile.name  = name
                            profile.phone = phone.isEmpty ? nil : phone
                            isSaving = true
                            if let updated = try? await service.updateProfile(profile) {
                                userStore.currentUser = updated
                            }
                            isSaving = false
                            dismiss()
                        }
                    }
                    .bold()
                    .foregroundStyle(Color.brandTeal)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Family Members View
struct FamilyMembersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserStore.self) private var userStore
    let userRole: UserRole

    var body: some View {
        NavigationStack {
            List {
                Section("成員列表（\(userStore.familyMembers.count) 位）") {
                    ForEach(userStore.familyMembers) { member in
                        HStack(spacing: 14) {
                            ZStack(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(Color.brandTealLight)
                                    .frame(width: 48, height: 48)
                                Image(systemName: member.role == .caregiver ? "cross.case.fill" : "person.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.brandTeal)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(member.name)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(member.role?.displayName ?? "-")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(member.role == .caregiver ? Color.brandTeal : .orange)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

                if userRole == .family,
                   let inviteCode = userStore.currentUser?.family?.id {
                    Section("邀請新成員") {
                        HStack {
                            Image(systemName: "qrcode")
                                .foregroundStyle(Color.brandTeal)
                                .frame(width: 24)
                            Text("邀請碼：\(inviteCode.prefix(8).uppercased())")
                                .font(.system(size: 15, weight: .medium))
                            Spacer()
                        }
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
