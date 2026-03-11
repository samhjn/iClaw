import SwiftUI

struct SessionRowView: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
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

                Spacer()

                Text("\(session.messages.count) messages")
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
