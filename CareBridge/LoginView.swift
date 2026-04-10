import SwiftUI

struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @State private var email = ""
    @State private var password = ""
    @State private var showJoinFamily = false

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color.brandBackground, Color.brandTealLight.opacity(0.5), Color.brandTealLight],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

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
                                Button("FORGOT? \u{2022} 忘記密碼?") { }
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

                        // Login button
                        Button {
                            withAnimation { isLoggedIn = true }
                        } label: {
                            HStack {
                                Spacer()
                                Text("登入 Login")
                                    .font(.system(size: 17, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                            }
                            .foregroundStyle(.white)
                            .padding(.vertical, 16)
                            .background(
                                Capsule().fill(Color.brandTeal)
                            )
                        }
                        .buttonStyle(.plain)

                        // Fast access
                        VStack(spacing: 12) {
                            Text("FAST ACCESS \u{2022} 快速存取")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 32) {
                                VStack(spacing: 6) {
                                    Image(systemName: "faceid")
                                        .font(.system(size: 28))
                                        .foregroundStyle(Color.brandTeal)
                                    Text("FACE ID")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                VStack(spacing: 6) {
                                    Image(systemName: "touchid")
                                        .font(.system(size: 28))
                                        .foregroundStyle(Color.brandTeal)
                                    Text("TOUCH ID")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
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
                            showJoinFamily = true
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.brandTeal)
                        Text("\u{2022}")
                            .foregroundStyle(.secondary)
                        Button("加入家庭") {
                            showJoinFamily = true
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
            }
            .scrollIndicators(.hidden)
        }
        .fullScreenCover(isPresented: $showJoinFamily) {
            JoinFamilyView(isLoggedIn: $isLoggedIn)
        }
    }
}

#Preview {
    LoginView(isLoggedIn: .constant(false))
}
