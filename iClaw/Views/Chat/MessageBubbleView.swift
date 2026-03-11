import SwiftUI

struct MessageBubbleView: View {
    var message: Message?
    var streamingContent: String?

    private var role: MessageRole {
        message?.role ?? .assistant
    }

    private var content: String {
        streamingContent ?? message?.content ?? ""
    }

    private var isUser: Bool {
        role == .user
    }

    private var isTool: Bool {
        role == .tool
    }

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if isTool {
                    toolCallView
                } else {
                    bubbleView
                }

                if let msg = message {
                    Text(msg.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !isUser { Spacer(minLength: 48) }
        }
    }

    private var bubbleView: some View {
        Text(content)
            .font(.body)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isUser ? Color.accentColor : Color(.systemGray6))
            )
            .foregroundStyle(isUser ? .white : .primary)
    }

    @ViewBuilder
    private var toolCallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let name = message?.name {
                Label(name, systemImage: "wrench")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            Text(content)
                .font(.caption)
                .fontDesign(.monospaced)
                .lineLimit(8)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray5))
        )
    }
}
