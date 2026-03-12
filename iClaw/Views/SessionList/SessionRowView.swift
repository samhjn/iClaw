import SwiftUI

struct SessionRowView: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if session.isActive {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
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

            if let lastMessage = session.sortedMessages.last,
               let content = lastMessage.content {
                Text(content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
