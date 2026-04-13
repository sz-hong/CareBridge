import SwiftUI

struct JoinFamilyView: View {
    @Binding var isLoggedIn: Bool
    @Binding var userRole: UserRole
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dataService) private var service
    @Environment(UserStore.self) private var userStore
    @State private var selectedRole: UserRole = .family
    @State private var inviteCode: [String] = ["", "", "", "", "", ""]
    @FocusState private var focusedField: Int?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isCodeComplete: Bool {
        inviteCode.allSatisfy { !$0.isEmpty }
    }

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
                    // Close button
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color(.systemGray6)))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Header icon
                    Image(systemName: "person.2.badge.gearshape")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.brandTeal)

                    // Title
                    VStack(spacing: 6) {
                        Text("Join Your Family")
                            .font(.system(size: 30, weight: .bold))
                        Text("加入您的家庭")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.secondary)
                    }

                    // Role selection card
                    VStack(spacing: 14) {
                        Text("選擇您的身份 / Select Your Role")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            roleCard(role: .family, icon: "figure.and.child.holdinghands",
                                     title: "家屬", subtitle: "Family")
                            roleCard(role: .caregiver, icon: "cross.case.fill",
                                     title: "看護", subtitle: "Caregiver")
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.white.opacity(0.85))
                    )
                    .padding(.horizontal, 16)

                    // Invite code card
                    VStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Image(systemName: "envelope.open.fill")
                                .foregroundStyle(Color.brandTeal)
                            Text("Enter Invite Code")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Text("輸入邀請碼")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        // 6-digit code input
                        HStack(spacing: 10) {
                            ForEach(0..<6, id: \.self) { index in
                                TextField("", text: $inviteCode[index])
                                    .frame(width: 44, height: 52)
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 22, weight: .bold))
                                    .keyboardType(.numberPad)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(.systemGray6))
                                    )
                                    .focused($focusedField, equals: index)
                                    .onChange(of: inviteCode[index]) { _, newValue in
                                        if newValue.count > 1 {
                                            inviteCode[index] = String(newValue.suffix(1))
                                        }
                                        if !newValue.isEmpty && index < 5 {
                                            focusedField = index + 1
                                        }
                                    }
                            }
                        }

                        // Error message
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Join button
                        Button {
                            Task { await performJoin() }
                        } label: {
                            HStack {
                                Spacer()
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Join Family / 加入家庭")
                                        .font(.system(size: 16, weight: .semibold))
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                Spacer()
                            }
                            .foregroundStyle(.white)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(isCodeComplete ? Color.brandTeal : Color.gray))
                        }
                        .buttonStyle(.plain)
                        .disabled(!isCodeComplete || isLoading)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.white.opacity(0.85))
                    )
                    .padding(.horizontal, 16)

                    // OR divider
                    HStack(spacing: 12) {
                        Rectangle().fill(Color(.systemGray4)).frame(height: 1)
                        Text("OR / 或")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Rectangle().fill(Color(.systemGray4)).frame(height: 1)
                    }
                    .padding(.horizontal, 40)

                    // QR code card
                    VStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "qrcode.viewfinder")
                                .foregroundStyle(Color.brandTeal)
                            Text("Scan QR Code")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Text("掃描二維碼")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.white.opacity(0.85))
                    )
                    .padding(.horizontal, 16)

                    // Bottom links
                    VStack(spacing: 12) {
                        Button { } label: {
                            Text("Create New Family")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.brandTeal)
                        }
                        Text("建立新家庭")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Button { dismiss() } label: {
                            Text("Skip for now")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        Text("略過此步")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }

                    Spacer(minLength: 40)
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func performJoin() async {
        errorMessage = nil
        isLoading = true
        let code = inviteCode.joined()
        do {
            let response = try await service.joinFamily(inviteCode: code, role: selectedRole)
            userStore.populate(from: response)
            userStore.load()
            await MainActor.run {
                userRole = response.user.role ?? selectedRole
                withAnimation { isLoggedIn = true }
            }
        } catch {
            await MainActor.run {
                errorMessage = "邀請碼無效，請確認後重試"
                isLoading = false
            }
        }
    }

    private func roleCard(role: UserRole, icon: String, title: String, subtitle: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedRole = role }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(selectedRole == role ? .white : Color.brandTeal)
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(selectedRole == role ? .white : .primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(selectedRole == role ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selectedRole == role ? Color.brandTeal : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selectedRole == role ? Color.brandTeal : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    JoinFamilyView(isLoggedIn: .constant(false), userRole: .constant(.family))
}
