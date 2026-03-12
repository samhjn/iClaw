import SwiftUI

struct InputBarView: View {
    @Binding var text: String
    let isLoading: Bool
    var isBlocked: Bool = false
    var isCancelling: Bool = false
    let onSend: () -> Void
    var onStop: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message...", text: $text, axis: .vertical)
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
                        .stroke(isBlocked ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
                )
                .focused($isFocused)

            if isLoading, let onStop {
                Button {
                    onStop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red)
                }
                .disabled(isCancelling)
            } else {
                Button {
                    onSend()
                } label: {
                    Image(systemName: isBlocked ? "lock.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isBlocked ? .orange : .accentColor)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading || isBlocked)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
