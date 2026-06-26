import SwiftUI

struct SignUpView: View {
    @Binding var isLoggedIn: Bool
    @Binding var userRole: UserRole
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dataService) private var service
    @Environment(UserStore.self) private var userStore

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var phone = ""
    @State private var language: String = SupportedLanguage.defaultFromLocale
    @State private var isRegistering = false
    @State private var errorMessage: String? = nil
    @FocusState private var isPhoneFocused: Bool

    private var canRegister: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 8 &&
        password == confirmPassword
    }

    private var passwordMismatch: Bool {
        !confirmPassword.isEmpty && password != confirmPassword
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.brandBackground, Color.brandTealLight.opacity(0.5), Color.brandTealLight],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 40)

                    // Logo
                    VStack(spacing: 8) {
                        Image(systemName: "cross.case.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.brandTeal)
                        Text("CareBridge")
                            .font(.system(size: 32, weight: .bold))
                        Text("CONNECTED CARE  \u{2022}  連結照護")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 4)

                    // Form card
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("建立帳號  \u{2022}  Sign Up")
                                .font(.system(size: 24, weight: .bold))
                            Text("Create your CareBridge account to get started.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }

                        // 姓名
                        inputField(label: "NAME / 姓名", icon: "person") {
                            TextField("您的全名", text: $name)
                                .textContentType(.name)
                                .autocorrectionDisabled()
                        }

                        // 電子郵件
                        inputField(label: "EMAIL / 電子郵件", icon: "envelope") {
                            TextField("name@carebridge.com", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }

                        // 密碼
                        inputField(label: "PASSWORD / 密碼", icon: "lock") {
                            SecureField("至少 8 個字元", text: $password)
                                .textContentType(.newPassword)
                        }

                        // 確認密碼
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CONFIRM PASSWORD / 確認密碼")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(passwordMismatch ? .red : .secondary)
                                    .frame(width: 20)
                                SecureField("再次輸入密碼", text: $confirmPassword)
                                    .textContentType(.newPassword)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(passwordMismatch ? Color.red.opacity(0.08) : Color(.systemGray6))
                            )
                            if passwordMismatch {
                                Text("密碼不一致")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red)
                            }
                        }

                        // 電話（選填）
                        inputField(label: "PHONE / 電話（選填）", icon: "phone") {
                            TextField("0912345678", text: $phone)
                                .textContentType(.telephoneNumber)
                                .keyboardType(.phonePad)
                                .focused($isPhoneFocused)
                        }

                        // 語言
                        VStack(alignment: .leading, spacing: 6) {
                            Text("LANGUAGE / 慣用語言")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                Image(systemName: "globe")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Picker("", selection: $language) {
                                    ForEach(SupportedLanguage.all, id: \.code) { lang in
                                        Text(lang.displayName).tag(lang.code)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.primary)
                                Spacer()
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                        }

                        // 錯誤訊息
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // 註冊按鈕
                        Button {
                            Task { await performRegister() }
                        } label: {
                            HStack {
                                Spacer()
                                if isRegistering {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("建立帳號 Sign Up")
                                        .font(.system(size: 17, weight: .semibold))
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                Spacer()
                            }
                            .foregroundStyle(.white)
                            .padding(.vertical, 16)
                            .background(Capsule().fill(canRegister ? Color.brandTeal : Color.gray))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canRegister || isRegistering)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(.white.opacity(0.85))
                    )
                    .padding(.horizontal, 16)

                    // 返回登入
                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Button("Sign In") { dismiss() }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.brandTeal)
                    }

                    Spacer(minLength: 20)
                }
                .frame(maxWidth: usesWideLayout ? 560 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar {
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

    // MARK: - Subviews

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private func inputField<Content: View>(label: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                content()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
        }
    }

    // MARK: - Actions

    private func performRegister() async {
        errorMessage = nil
        isRegistering = true
        do {
            let response = try await service.register(
                name: name.trimmingCharacters(in: .whitespaces),
                email: email.trimmingCharacters(in: .whitespaces),
                password: password,
                phone: phone.isEmpty ? nil : phone,
                language: language
            )
            userStore.populate(from: response)
            // Role is unset until user joins/creates a family
            await MainActor.run {
                userRole = response.user.role ?? .family
                withAnimation { isLoggedIn = true }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isRegistering = false
            }
        }
    }
}

#Preview {
    SignUpView(isLoggedIn: .constant(false), userRole: .constant(.family))
        .environment(UserStore())
}
