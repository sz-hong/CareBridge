import SwiftUI

struct KeyboardDoneButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("完成")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.brandTeal)
                .frame(width: 72, height: 44)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: .capsule)
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.7), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .padding(.bottom, 8)
    }
}
