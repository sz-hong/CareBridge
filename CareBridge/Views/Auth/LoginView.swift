import SwiftUI
import LocalAuthentication

struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @Binding var userRole: UserRole
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false
    @State private var showForgotPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    @Environment(\.dataService) private var service
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(UserStore.self) private var userStore
    @Environment(LocaleStore.self) private var localeStore

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color.brandBackground, Color.brandTealLight.opacity(0.5), Color.brandTealLight],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Language picker — top-right corner. Available before login so
            // users can switch the UI language without an account first.
            VStack {
                HStack {
                    Spacer()
                    Menu {
                        ForEach(SupportedLanguage.all, id: \.code) { lang in
                            Button {
                                localeStore.code = lang.code
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
                            Image(systemName: "globe")
                            Text(SupportedLanguage.displayName(for: localeStore.code))
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(Color.brandTeal)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.ultraThinMaterial))
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                Spacer()
            }
            .ignoresSafeArea(.keyboard)
            .zIndex(1)

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 40)

                    // Logo + Branding
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
                    .padding(.bottom, 8)

                    // Login card
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("登入  \u{2022}  Login")
                                .font(.system(size: 24, weight: .bold))
                            Text("Please enter your credentials to continue.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }

                        // Email field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("EMAIL / 電子郵件")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                Image(systemName: "envelope")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                TextField("name@carebridge.com", text: $email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                        }

                        // Password field
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("PASSWORD / 密碼")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("FORGOT? \u{2022} 忘記密碼?") { showForgotPassword = true }
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.brandTeal)
                            }
                            HStack(spacing: 10) {
                                Image(systemName: "lock")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                SecureField("\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}", text: $password)
                                    .textContentType(.password)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                        }

                        // Error message
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Login button
                        Button {
                            Task { await performLogin() }
                        } label: {
                            HStack {
                                Spacer()
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("登入 Login")
                                        .font(.system(size: 17, weight: .semibold))
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                Spacer()
                            }
                            .foregroundStyle(.white)
                            .padding(.vertical, 16)
                            .background(
                                Capsule().fill(canLogin ? Color.brandTeal : Color.gray)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canLogin || isLoading)

                        // Fast access
                        VStack(spacing: 12) {
                            Text("FAST ACCESS \u{2022} 快速存取")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 32) {
                                Button { Task { await performBiometricLogin() } } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: "faceid")
                                            .font(.system(size: 28))
                                            .foregroundStyle(Color.brandTeal)
                                        Text("FACE ID")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                Button { Task { await performBiometricLogin() } } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: "touchid")
                                            .font(.system(size: 28))
                                            .foregroundStyle(Color.brandTeal)
                                        Text("TOUCH ID")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(.white.opacity(0.85))
                    )
                    .padding(.horizontal, 16)

                    // Sign up
                    HStack(spacing: 4) {
                        Text("Don't have an account?")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Button("Sign Up") {
                            showSignUp = true
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.brandTeal)
                    }

                    // Footer links
                    HStack(spacing: 16) {
                        Button("Privacy Policy") { }
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Button("Terms of Service") { }
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 20)
                }
                .frame(maxWidth: usesWideLayout ? 560 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .fullScreenCover(isPresented: $showSignUp) {
            SignUpView(isLoggedIn: $isLoggedIn, userRole: $userRole)
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
        }
    }

    private var canLogin: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private func performLogin() async {
        errorMessage = nil
        isLoading = true
        do {
            let response = try await service.login(email: email, password: password)
            userStore.populate(from: response)
            userStore.load()   // async fetch family members
            userRole = response.user.role ?? .family
            await MainActor.run { withAnimation { isLoggedIn = true } }
        } catch {
            print("🔴 Login failed: \(error)")
            if let decodingError = error as? DecodingError {
                print("🔴 DecodingError detail: \(decodingError)")
            }
            await MainActor.run {
                errorMessage = "帳號或密碼錯誤，請重試"
                isLoading = false
            }
        }
    }

    private func performBiometricLogin() async {
        // Must have logged in with password at least once before — that's when
        // the refresh token was stored in Keychain.
        guard KeychainService.refreshToken != nil else {
            await MainActor.run { errorMessage = "請先使用帳號密碼登入一次，之後才能使用生物辨識" }
            return
        }

        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            await MainActor.run { errorMessage = "此裝置不支援生物辨識" }
            return
        }

        do {
            let biometricOK = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "使用生物辨識登入 CareBridge"
            )
            guard biometricOK else { return }
        } catch {
            await MainActor.run { errorMessage = "生物辨識失敗，請使用帳號密碼登入" }
            return
        }

        // Biometric passed → exchange refresh token for a fresh session.
        guard let api = service as? APIDataService else {
            await MainActor.run { errorMessage = "目前環境不支援生物辨識登入" }
            return
        }
        do {
            let profile = try await api.loginWithStoredRefreshToken()
            userStore.currentUser = profile
            userStore.load()
            userRole = profile.role ?? .family
            await MainActor.run { withAnimation { isLoggedIn = true } }
        } catch {
            await MainActor.run {
                errorMessage = "登入憑證已過期，請重新使用帳號密碼登入"
            }
        }
    }
}

// MARK: - Forgot Password View
struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var email = ""
    @State private var isSent = false

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Image(systemName: "lock.rotation")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.brandTeal)
                    .padding(.top, 16)

                VStack(spacing: 8) {
                    Text("重設密碼")
                        .font(.system(size: 26, weight: .bold))
                    Text("輸入您的電子郵件，我們將發送重設連結")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if isSent {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.green)
                        Text("重設連結已發送")
                            .font(.system(size: 18, weight: .semibold))
                        Text("請檢查 \(email) 的收件匣")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6)))
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("電子郵件")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Image(systemName: "envelope")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            TextField("name@carebridge.com", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                    }
                    .padding(.horizontal, 4)

                    Button {
                        withAnimation { isSent = true }
                    } label: {
                        Text("發送重設連結")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(email.isEmpty ? Color.gray : Color.brandTeal))
                    }
                    .buttonStyle(.plain)
                    .disabled(email.isEmpty)
                }

                Spacer()
            }
            .frame(maxWidth: usesWideLayout ? 560 : .infinity)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .navigationTitle("忘記密碼")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("關閉") { dismiss() }
                        .foregroundStyle(Color.brandTeal)
                }
            }
        }
    }
}

#Preview {
    LoginView(isLoggedIn: .constant(false), userRole: .constant(.family))
        .environment(UserStore())
        .environment(LocaleStore())
}
