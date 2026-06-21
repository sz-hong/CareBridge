import SwiftUI
import UIKit

struct PhotoPreviewItem: Identifiable {
    let id: String
    let image: UIImage
    let sourceFrame: CGRect
    let sourceCornerRadius: CGFloat
}

@MainActor
private enum RemotePhotoCache {
    static let images = NSCache<NSURL, UIImage>()

    static func image(for url: URL) async -> UIImage? {
        if let cached = images.object(forKey: url as NSURL) {
            return cached
        }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode,
              let image = UIImage(data: data) else {
            return nil
        }

        images.setObject(image, forKey: url as NSURL)
        return image
    }
}

struct CachedRemotePhoto<Content: View, Placeholder: View>: View {
    let url: URL
    let content: (UIImage) -> Content
    let placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                content(image)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            image = await RemotePhotoCache.image(for: url)
        }
    }
}

struct PreviewablePhotoSource<Content: View>: View {
    let id: String
    let image: UIImage
    let sourceCornerRadius: CGFloat
    let isPreviewed: Bool
    let onPreview: (PhotoPreviewItem) -> Void
    @ViewBuilder let content: () -> Content

    @State private var sourceFrame = CGRect.zero

    var body: some View {
        Button {
            guard sourceFrame.width > 0, sourceFrame.height > 0 else { return }
            onPreview(
                PhotoPreviewItem(
                    id: id,
                    image: image,
                    sourceFrame: sourceFrame,
                    sourceCornerRadius: sourceCornerRadius
                )
            )
        } label: {
            content()
                .opacity(isPreviewed ? 0 : 1)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { newFrame in
                    sourceFrame = newFrame
                }
        }
        .buttonStyle(.plain)
    }
}

struct PhotoPreviewOverlay: View {
    let item: PhotoPreviewItem
    let onDismiss: () -> Void

    @State private var isExpanded = false
    @State private var isDismissing = false

    private let animation = Animation.spring(
        response: 0.38,
        dampingFraction: 0.86
    )

    var body: some View {
        GeometryReader { proxy in
            let overlayFrame = proxy.frame(in: .global)
            let sourceFrame = item.sourceFrame.offsetBy(
                dx: -overlayFrame.minX,
                dy: -overlayFrame.minY
            )
            let targetFrame = targetFrame(in: proxy.size)
            let displayedFrame = isExpanded ? targetFrame : sourceFrame

            ZStack {
                Color.black
                    .opacity(isExpanded ? 0.52 : 0)
                    .ignoresSafeArea()
                    .contentShape(.rect)
                    .onTapGesture(perform: dismiss)

                Image(uiImage: item.image)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: max(displayedFrame.width, 1),
                        height: max(displayedFrame.height, 1)
                    )
                    .clipShape(
                        .rect(
                            cornerRadius: isExpanded
                                ? 20
                                : item.sourceCornerRadius
                        )
                    )
                    .position(
                        x: displayedFrame.midX,
                        y: displayedFrame.midY
                    )
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                    .allowsHitTesting(false)
                    .accessibilityLabel("照護照片預覽")
                    .accessibilityAddTraits(.isImage)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(animation) {
                isExpanded = true
            }
        }
    }

    private func targetFrame(in containerSize: CGSize) -> CGRect {
        let maximumSize = CGSize(
            width: max(containerSize.width - 32, 1),
            height: max(containerSize.height - 96, 1)
        )
        let imageSize = item.image.size
        let imageAspectRatio = max(imageSize.width / max(imageSize.height, 1), 0.01)
        let availableAspectRatio = maximumSize.width / maximumSize.height

        let size: CGSize
        if imageAspectRatio > availableAspectRatio {
            size = CGSize(
                width: maximumSize.width,
                height: maximumSize.width / imageAspectRatio
            )
        } else {
            size = CGSize(
                width: maximumSize.height * imageAspectRatio,
                height: maximumSize.height
            )
        }

        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true

        withAnimation(animation, completionCriteria: .logicallyComplete) {
            isExpanded = false
        } completion: {
            onDismiss()
        }
    }
}
