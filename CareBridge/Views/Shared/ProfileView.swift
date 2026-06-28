import SwiftUI

struct ProfileView: View {
    @Binding var isLoggedIn: Bool
    let userRole: UserRole
    var isModal = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(UserStore.self) private var userStore
    @Environment(LocaleStore.self) private var localeStore
    @Environment(\.dataService) private var service
    @Environment(\.floatingActionBottomPadding) private var floatingActionBottomPadding
    @State private var showLogoutConfirm = false
    @State private var showEditProfile = false
    @State private var showFamilyMembers = false
    @State private var showNotificationPrefs = false
    @State private var showNotifications = false
    @State private var inviteCodeCopied = false
    @Environment(HealthKitSyncManager.self) private var healthSync
    @AppStorage("carebridge.healthSyncEnabled") private var healthSyncEnabled = false
    @State private var healthBinding: HealthBindingState?
    @State private var bindingError: String?
    @State private var bindingBusy = false
    @State private var showHealthBindingConflict = false

    private var user: UserProfile? { userStore.currentUser }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if !isModal {
                        RootPageHeader {
                            showNotifications = true
                        } title: {
                            Text("個人/設定")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .padding(.top, 4)
                        .frame(maxWidth: usesWideLayout ? 720 : .infinity)
                        .frame(maxWidth: .infinity)
                    }

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
                .listRowBackground(Color(.systemBackground))

                // Personal info
                Section("個人資訊") {
                    profileRow(icon: "person.text.rectangle", label: "姓名", value: user?.name ?? "-")
                    profileRow(icon: "phone.fill", label: "電話", value: user?.phone ?? "-")
                    profileRow(icon: "envelope.fill", label: "電子郵件", value: user?.email ?? "-")
                    if isModal {
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
                }
                .listRowBackground(Color(.systemBackground))

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
                .listRowBackground(Color(.systemBackground))

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
                    // 與健康 App 的綁定：同一個家庭只能有一支裝置開啟同步，
                    // 避免雙裝置同時往 backend 推同類型生理資料造成雜訊。
                    // 真正的 single-binding 規則由後端 `/families/me/health-
                    // binding/` 強制（health-data/sync/ 會檢查 owner），這裡
                    // 只是把開關綁到那個 API。
                    Toggle(isOn: healthSyncBinding) {
                        HStack(spacing: 12) {
                            Image(systemName: "heart.text.square.fill")
                                .foregroundStyle(.red)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("與健康同步")
                                if let sub = healthSyncSubtitle {
                                    Text(sub)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .tint(Color.brandTeal)
                    .disabled(bindingBusy || isBoundByOther)

                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .foregroundStyle(Color.brandTeal)
                            .frame(width: 24)
                        Text("語言")
                        Spacer()
                        Menu {
                            ForEach(SupportedLanguage.all, id: \.code) { lang in
                                Button {
                                    Task { await updateLanguage(lang.code) }
                                } label: {
                                    if lang.code == localeStore.code {
                                        Label(lang.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(lang.displayName)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(SupportedLanguage.displayName(for: localeStore.code))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listRowBackground(Color(.systemBackground))

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
                .listRowBackground(Color(.systemBackground))
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.brandBackground.ignoresSafeArea())
                    .frame(maxWidth: usesWideLayout ? 720 : .infinity)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(isModal ? "個人資料" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(isModal ? .visible : .hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) {
                if !isModal {
                    Button {
                        showEditProfile = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(.systemBackground))
                                .frame(width: 52, height: 52)
                                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
                            Image(systemName: "pencil")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(.trailing, usesWideLayout ? 32 : 24)
                    .padding(.bottom, floatingActionBottomPadding)
                    .accessibilityLabel("編輯個人資料")
                }
            }
            .toolbar {
                if isModal {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showNotifications) {
                NotificationCenterView()
            }
            .alert("此家庭已綁定其他裝置", isPresented: $showHealthBindingConflict) {
                Button("確定", role: .cancel) { }
            } message: {
                Text("為避免重複資料，每個家庭只能由一支裝置同步健康資料。請先在原裝置關閉同步後再試。")
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
            .alert("無法切換健康同步", isPresented: Binding(
                get: { bindingError != nil },
                set: { if !$0 { bindingError = nil } }
            )) {
                Button("確定", role: .cancel) { bindingError = nil }
            } message: {
                Text(bindingError ?? "")
            }
            .task {
                await refreshHealthBinding()
            }
        }
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    // MARK: - Health Binding Helpers

    private var isOwnerBinding: Bool { healthBinding?.isOwner == true }
    private var isBoundByOther: Bool {
        (healthBinding?.isBound == true) && healthBinding?.isOwner == false
    }

    private var healthSyncSubtitle: String? {
        if let b = healthBinding {
            if b.isOwner { return "此裝置為本家庭的健康資料來源" }
            if b.isBound { return "目前由 \(b.userName ?? "其他成員") 同步" }
        }
        return nil
    }

    /// `Binding<Bool>` 把 Toggle 接到後端的 claim/release。Toggle 切下去
    /// → 觸發 API → 成功才更新本地 healthSyncEnabled 並啟動 observer。
    private var healthSyncBinding: Binding<Bool> {
        Binding(
            get: { isOwnerBinding && healthSyncEnabled },
            set: { newValue in
                Task { await toggleHealthSync(newValue) }
            }
        )
    }

    private func refreshHealthBinding() async {
        guard user?.family != nil else { return }
        if let state = try? await service.fetchHealthBinding() {
            healthBinding = state
            // 後端權威：若本機 flag 還亮著但 binding 已經不是自己（例如其
            // 他裝置 claim 走了），自動關掉，避免一直送注定 403 的 sync。
            if !state.isOwner { healthSyncEnabled = false }
        }
    }

    private func toggleHealthSync(_ on: Bool) async {
        guard !bindingBusy else { return }
        bindingBusy = true
        defer { bindingBusy = false }

        do {
            if on {
                let label = await MainActor.run { UIDevice.current.name }
                let state = try await service.claimHealthBinding(
                    deviceId: deviceIdentifier,
                    deviceLabel: label,
                )
                healthBinding = state
                healthSyncEnabled = true
                await healthSync.startSyncing()
            } else {
                let state = try await service.releaseHealthBinding()
                healthBinding = state
                healthSyncEnabled = false
            }
        } catch HealthBindingError.conflict {
            await refreshHealthBinding()
            showHealthBindingConflict = true
        } catch {
            bindingError = error.localizedDescription
        }
    }

    private func updateLanguage(_ code: String) async {
        // Apply UI locale immediately so the rest of the app re-renders in
        // the new language even if the backend update is slow / fails.
        localeStore.code = code

        guard var profile = userStore.currentUser, profile.language != code else { return }
        profile.language = code
        if let updated = try? await service.updateProfile(profile) {
            userStore.currentUser = updated
        }
    }

    /// 在 UserDefaults 持久化的「本機裝置識別」。第一次取用時生成一個 UUID，
    /// 之後跨啟動穩定。用來判斷此家庭的健康同步綁定是否在本機。
    private var deviceIdentifier: String {
        let key = "carebridge.deviceUUID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    /// `label` 是 UI 字串（會走 Localizable.xcstrings），`value` 是後端帶下來
    /// 的個資（姓名/電話/email 等），故意保留原始 String 不過 LocalizedStringKey
    /// —— 個資不能被當成 key 去查翻譯表。
    private func profileRow(icon: String, label: LocalizedStringKey, value: String) -> some View {
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var name = ""
    @State private var phone = ""
    @State private var isSaving = false
    @FocusState private var isPhoneFocused: Bool

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

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
                            .textContentType(.telephoneNumber)
                            .focused($isPhoneFocused)
                    }
                }
                .listRowBackground(Color(.systemBackground))

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
                .listRowBackground(Color(.systemBackground))
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: usesWideLayout ? 640 : .infinity)
            .frame(maxWidth: .infinity)
            .scrollContentBackground(.hidden)
            .background(Color.brandBackground.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
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
                ToolbarItemGroup(placement: .keyboard) {
                    if isPhoneFocused {
                        Spacer()
                        KeyboardDoneButton {
                            isPhoneFocused = false
                        }
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
    }
}

// MARK: - Family Members View
struct FamilyMembersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserStore.self) private var userStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let userRole: UserRole

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

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
                .listRowBackground(Color(.systemBackground))

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
                    .listRowBackground(Color(.systemBackground))
                }
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: usesWideLayout ? 720 : .infinity)
            .frame(maxWidth: .infinity)
            .scrollContentBackground(.hidden)
            .background(Color.brandBackground.ignoresSafeArea())
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var medicationReminder = true
    @State private var careLogUpdate = true
    @State private var sosAlert = true
    @State private var todoAssigned = true
    @State private var calendarEvent = true
    @State private var chatMessage = true
    @State private var leaveRequest = false
    @State private var purchaseRequest = false

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("照護通知") {
                    Toggle("用藥提醒", isOn: $medicationReminder)
                    Toggle("照護日誌更新", isOn: $careLogUpdate)
                    Toggle("SOS 緊急警報", isOn: $sosAlert)
                }
                .listRowBackground(Color(.systemBackground))

                Section("任務與行程") {
                    Toggle("待辦事項指派", isOn: $todoAssigned)
                    Toggle("行事曆提醒", isOn: $calendarEvent)
                }
                .listRowBackground(Color(.systemBackground))

                Section("溝通") {
                    Toggle("新聊天訊息", isOn: $chatMessage)
                    Toggle("請假申請", isOn: $leaveRequest)
                    Toggle("採購需求", isOn: $purchaseRequest)
                }
                .listRowBackground(Color(.systemBackground))

                Section {
                    Text("通知將透過 APNs 推播送達。您可以隨時在 iOS 設定中管理推播權限。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color(.systemBackground))
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: usesWideLayout ? 640 : .infinity)
            .frame(maxWidth: .infinity)
            .scrollContentBackground(.hidden)
            .background(Color.brandBackground.ignoresSafeArea())
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
        .environment(UserStore())
        .environment(LocaleStore())
}
