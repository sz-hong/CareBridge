import SwiftUI

struct RootPageHeader<Title: View>: View {
    let horizontalPadding: CGFloat
    let notificationAction: () -> Void
    private let title: Title

    init(
        horizontalPadding: CGFloat = 16,
        notificationAction: @escaping () -> Void,
        @ViewBuilder title: () -> Title
    ) {
        self.horizontalPadding = horizontalPadding
        self.notificationAction = notificationAction
        self.title = title()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            title
                .frame(maxWidth: .infinity, alignment: .leading)

            NotificationBellButton(style: .prominent) {
                notificationAction()
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }
}
