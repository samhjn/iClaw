import SwiftUI
import PhotosUI

struct InputBarView: View {
    @Binding var text: String
    let isLoading: Bool
    var isCompressing: Bool = false
    var isBlocked: Bool = false
    var isCancelling: Bool = false
    var cancelFailureReason: String?
    var pendingImages: [ImageAttachment] = []
    let onSend: () -> Void
    var onStop: (() -> Void)?
    var onStopCompression: (() -> Void)?
    var onDismissKeyboard: (() -> Void)?
    var onAddImage: ((UIImage) -> Void)?
    var onRemoveImage: ((UUID) -> Void)?

    @FocusState private var isFocused: Bool
    @State private var showImageSourcePicker = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    private var isBusy: Bool { isLoading || isCompressing }

    private var canSendMessage: Bool {
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty) && !isBusy && !isBlocked
    }

    var body: some View {
        VStack(spacing: 0) {
            if let reason = cancelFailureReason {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !pendingImages.isEmpty {
                ImageAttachmentBar(images: pendingImages) { id in
                    onRemoveImage?(id)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 8) {
                if isFocused {
                    Button {
                        onDismissKeyboard?()
                        isFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 36)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                Button {
                    showImageSourcePicker = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 36)
                }
                .disabled(isBusy)

                TextField(L10n.Chat.messagePlaceholder, text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isBlocked ? Color.orange.opacity(0.08) : Color(.systemGray6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(isFocused ? Color.accentColor.opacity(0.4) :
                                    isBlocked ? Color.orange.opacity(0.3) : Color.clear,
                                    lineWidth: 1)
                    )
                    .focused($isFocused)

                actionButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .animation(.easeInOut(duration: 0.2), value: cancelFailureReason != nil)
        .animation(.easeInOut(duration: 0.2), value: pendingImages.count)
        .confirmationDialog(L10n.Chat.addImage, isPresented: $showImageSourcePicker) {
            Button(L10n.Chat.photoLibrary) {
                showPhotoPicker = true
            }
            Button(L10n.Chat.camera) {
                showCamera = true
            }
            if UIPasteboard.general.hasImages {
                Button(L10n.Chat.pasteFromClipboard) {
                    if let img = UIPasteboard.general.image {
                        onAddImage?(img)
                    }
                }
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        onAddImage?(image)
                    }
                }
                await MainActor.run { selectedPhotoItem = nil }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView { image in
                onAddImage?(image)
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if isLoading, let onStop {
            Button {
                onStop()
            } label: {
                ZStack {
                    Circle()
                        .fill(isCancelling ? Color.gray.opacity(0.15) : Color.red.opacity(0.12))
                        .frame(width: 36, height: 36)

                    if isCancelling {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(isCancelling)
            .transition(.scale.combined(with: .opacity))
        } else if isCompressing, let onStopCompression {
            Button {
                onStopCompression()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 36, height: 36)

                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.orange)
                }
            }
            .transition(.scale.combined(with: .opacity))
        } else {
            Button {
                onSend()
            } label: {
                Circle()
                    .fill(canSendMessage ? Color.accentColor : isBlocked ? Color.orange.opacity(0.3) : Color(.systemGray4))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: isBlocked ? "lock.fill" : "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(canSendMessage ? .white : isBlocked ? .orange : Color(.systemGray2))
                    }
            }
            .disabled(!canSendMessage)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Camera Picker (UIImagePickerController wrapper)

struct CameraPickerView: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
