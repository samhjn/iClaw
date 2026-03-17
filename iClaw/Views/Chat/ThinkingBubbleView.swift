import SwiftUI

struct ThinkingBubbleView: View {
    let content: String
    let isStreaming: Bool

    @State private var isExpanded = false

    private var shouldDefaultExpand: Bool {
        isStreaming || content.count < 200
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundStyle(.purple.opacity(0.8))

                    Text(L10n.Chat.thinkingProcess)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    if isStreaming {
                        ProgressView()
                            .controlSize(.mini)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 8)

                MarkdownContentView(content, isUser: false)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.purple.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.15), lineWidth: 0.5)
        )
        .onAppear {
            isExpanded = shouldDefaultExpand
        }
    }
}
