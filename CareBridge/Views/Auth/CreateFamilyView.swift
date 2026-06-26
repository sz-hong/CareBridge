import SwiftUI

struct CreateFamilyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dataService) private var dataService
    @Environment(UserStore.self) private var userStore
    @Binding var userRole: UserRole

    @State private var familyName = ""
    @State private var elderName = ""
    @State private var elderBirthDate = Calendar.current.date(
        from: DateComponents(year: 1945, month: 1, day: 1)) ?? Date()
    @State private var isCreating = false
    @State private var errorMessage: String? = nil

    private var canCreate: Bool {
        !familyName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !elderName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            Image(systemName: "house.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(Color.brandTeal)
                            Text("建立新家庭")
                                .font(.system(size: 20, weight: .bold))
                            Text("您將成為此家庭的主要家屬")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 8)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)

                Section("家庭資訊") {
                    LabeledContent("家庭名稱") {
                        TextField("例：王家", text: $familyName)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("被照護者（長者）資訊") {
                    LabeledContent("長者姓名") {
                        TextField("例：王大明", text: $elderName)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("長者生日", selection: $elderBirthDate,
                               displayedComponents: .date)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await performCreate() }
                    } label: {
                        HStack {
                            Spacer()
                            if isCreating {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "plus.circle.fill")
                                Text("建立家庭")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(canCreate ? Color.brandTeal : Color.gray)
                    .disabled(!canCreate || isCreating)
                }
            }
            .frame(maxWidth: usesWideLayout ? 640 : .infinity)
            .frame(maxWidth: .infinity)
            .navigationTitle("建立新家庭")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private func performCreate() async {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let birthDateStr = df.string(from: elderBirthDate)

        errorMessage = nil
        isCreating = true
        do {
            _ = try await dataService.createFamily(
                name: familyName.trimmingCharacters(in: .whitespaces),
                elderName: elderName.trimmingCharacters(in: .whitespaces),
                elderBirthDate: birthDateStr
            )
            // 刷新 user profile — family 欄位更新後 CareBridgeApp 自動切到主 App
            userStore.load()
            await MainActor.run {
                userRole = .family
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = "建立失敗，請稍後再試"
                isCreating = false
            }
        }
    }
}

#Preview {
    CreateFamilyView(userRole: .constant(.family))
        .environment(UserStore())
}
