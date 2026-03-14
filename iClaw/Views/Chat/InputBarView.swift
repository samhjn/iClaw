import SwiftUI

struct InputBarView: View {
    @Binding var text: String
    let isLoading: Bool
    var isCompressing: Bool = false
    var isBlocked: Bool = false
    var isCancelling: Bool = false
    var cancelFailureReason: String?
    let onSend: () -> Void
    var onStop: (() -> Void)?
    var onStopCompression: (() -> Void)?
    var onDismissKeyboard: (() -> Void)?

    @FocusState private var isFocused: Bool

    private var isBusy: Bool { isLoading || isCompressing }

    private var canSendMessage: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy && !isBlocked
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
