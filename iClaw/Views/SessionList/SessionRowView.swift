import SwiftUI

struct SessionRowView: View {
    let session: Session

    private var previewContent: String? {
        if session.isActive, let streaming = session.pendingStreamingContent, !streaming.isEmpty {
            return streaming
        }
        if let lastMessage = session.sortedMessages.last, let content = lastMessage.content {
            return content
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if session.isActive {
                    PulsingDot()
                }
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(session.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if let agentName = session.agent?.name {
                    Label(agentName, systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if session.isActive {
                    Text(L10n.Common.active)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.green))
                }

                Spacer()

                Text(L10n.Sessions.messagesCount(session.messages.count))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let content = previewContent {
                Text(content)
                    .font(.subheadline)
                    .foregroundStyle(session.isActive && session.pendingStreamingContent != nil ? .primary : .secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
