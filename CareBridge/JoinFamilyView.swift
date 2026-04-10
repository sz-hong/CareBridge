import SwiftUI

struct JoinFamilyView: View {
    @Binding var isLoggedIn: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var inviteCode: [String] = ["", "", "", "", "", ""]
    @FocusState private var focusedField: Int?

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

                        // Join button
                        Button {
                            withAnimation { isLoggedIn = true }
                        } label: {
                            HStack {
                                Spacer()
                                Text("Join Family / 加入家庭")
                                    .font(.system(size: 16, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                            }
                            .foregroundStyle(.white)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color.brandTeal))
                        }
                        .buttonStyle(.plain)
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
}

#Preview {
    JoinFamilyView(isLoggedIn: .constant(false))
}
