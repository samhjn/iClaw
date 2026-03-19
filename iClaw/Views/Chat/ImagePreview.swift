import SwiftUI
import UIKit

// MARK: - Coordinator

@Observable
final class ImagePreviewCoordinator {
    static let shared = ImagePreviewCoordinator()

    private(set) var image: UIImage?
    private(set) var isPresented = false

    func show(_ image: UIImage) {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        self.image = image
        withAnimation(.easeOut(duration: 0.25)) {
            isPresented = true
        }
    }

    func close(animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                isPresented = false
            }
        } else {
            isPresented = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.image = nil
        }
    }
}

// MARK: - Root Overlay Modifier

struct ImagePreviewRootModifier: ViewModifier {
    @State private var coordinator = ImagePreviewCoordinator.shared

    func body(content: Content) -> some View {
        content.overlay {
            if coordinator.isPresented, let image = coordinator.image {
                ImagePreviewOverlay(image: image)
                    .transition(.opacity)
            }
        }
    }
}

extension View {
    func imagePreviewOverlay() -> some View {
        modifier(ImagePreviewRootModifier())
    }
}

// MARK: - Image Preview Overlay

private struct ImagePreviewOverlay: View {
    let image: UIImage

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var dismissTranslation: CGSize = .zero
    @State private var isDismissing = false
    @State private var toastMessage: String?

    private var dismissProgress: CGFloat {
        guard !isDismissing else { return 1 }
        return min(abs(dismissTranslation.height) / 280, 1)
    }

    var body: some View {
        let bgOpacity: Double = isDismissing ? 0 : 1 - Double(dismissProgress) * 0.55
        let imageScale = scale > 1 ? scale : scale * (1 - dismissProgress * 0.12)
        let imageOffset = CGSize(
            width: panOffset.width + (scale <= 1 ? dismissTranslation.width * 0.4 : 0),
            height: panOffset.height + (scale <= 1 ? dismissTranslation.height : 0)
        )
        let controlsVisible = !isDismissing && dismissProgress < 0.3

        GeometryReader { _ in
            ZStack {
                Color.black.opacity(bgOpacity)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if scale <= 1 {
                            ImagePreviewCoordinator.shared.close()
                        }
                    }

                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(imageScale)
                    .offset(imageOffset)
                    .gesture(dragGesture)
                    .simultaneousGesture(magnificationGesture)
                    .onTapGesture(count: 2) { toggleZoom() }

                if controlsVisible {
                    VStack {
                        HStack {
                            Spacer()
                            Button { ImagePreviewCoordinator.shared.close() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .white.opacity(0.35))
                            }
                            .padding()
                        }
                        Spacer()
                        toolbar
                            .padding(.bottom, 48)
                    }
                }

                if let message = toastMessage {
                    VStack {
                        Spacer()
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(.black.opacity(0.7)))
                            .padding(.bottom, 110)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea()
        .statusBar(hidden: true)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 36) {
            Button {
                UIPasteboard.general.image = image
                flashToast(L10n.Common.copied)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.title3)
                    Text(L10n.Chat.copyImage)
                        .font(.caption)
                }
                .foregroundStyle(.white)
                .frame(minWidth: 60, minHeight: 44)
            }

            Button {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                flashToast(L10n.Chat.imageSaved)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title3)
                    Text(L10n.Chat.saveImageToPhotos)
                        .font(.caption)
                }
                .foregroundStyle(.white)
                .frame(minWidth: 60, minHeight: 44)
            }
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if scale > 1 {
                    panOffset = CGSize(
                        width: lastPanOffset.width + value.translation.width,
                        height: lastPanOffset.height + value.translation.height
                    )
                } else {
                    dismissTranslation = value.translation
                }
            }
            .onEnded { value in
                if scale > 1 {
                    lastPanOffset = panOffset
                    return
                }

                let vy = value.predictedEndTranslation.height - value.translation.height
                if abs(dismissTranslation.height) > 100 || abs(vy) > 600 {
                    isDismissing = true
                    let flyY: CGFloat = dismissTranslation.height > 0 ? 600 : -600
                    withAnimation(.easeOut(duration: 0.15)) {
                        dismissTranslation = CGSize(
                            width: dismissTranslation.width,
                            height: flyY
                        )
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        ImagePreviewCoordinator.shared.close(animated: false)
                    }
                } else {
                    withAnimation(.interpolatingSpring(stiffness: 350, damping: 30)) {
                        dismissTranslation = .zero
                    }
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = max(0.5, lastScale * value.magnification)
            }
            .onEnded { _ in
                let clamped = max(1.0, min(scale, 5.0))
                withAnimation(.interpolatingSpring(stiffness: 300, damping: 28)) {
                    scale = clamped
                    if clamped <= 1 {
                        panOffset = .zero
                        lastPanOffset = .zero
                    }
                }
                lastScale = clamped
            }
    }

    private func toggleZoom() {
        withAnimation(.interpolatingSpring(stiffness: 280, damping: 26)) {
            if scale > 1 {
                scale = 1
                lastScale = 1
                panOffset = .zero
                lastPanOffset = .zero
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    private func flashToast(_ message: String) {
        withAnimation { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { toastMessage = nil }
        }
    }
}
