import SwiftUI

struct ManagementView: View {
    @Binding var showProfile: Bool
    let userRole: UserRole
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedSection = ManagementSection.finance
    @State private var showNotifications = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RootPageHeader(horizontalPadding: usesWideLayout ? 32 : 16) {
                    showNotifications = true
                } title: {
                    Text("管理")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.top, 4)
                .frame(maxWidth: usesWideLayout ? 720 : .infinity)
                .frame(maxWidth: .infinity)

                Picker("管理分類", selection: $selectedSection) {
                    ForEach(ManagementSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, usesWideLayout ? 32 : 16)
                .padding(.bottom, 10)
                .frame(maxWidth: usesWideLayout ? 720 : .infinity)

                Group {
                    switch selectedSection {
                    case .finance:
                        SpendingView(
                            showProfile: $showProfile,
                            userRole: userRole,
                            isEmbeddedInManagement: true
                        )
                    case .documents:
                        DocumentsView(isEmbeddedInManagement: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.brandBackground)
            .navigationDestination(isPresented: $showNotifications) {
                NotificationCenterView()
            }
        }
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }
}

private enum ManagementSection: String, CaseIterable, Hashable, Identifiable {
    case finance
    case documents

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .finance: "財務"
        case .documents: "文件"
        }
    }
}
