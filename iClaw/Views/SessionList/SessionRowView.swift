import SwiftUI

struct SessionRowView: View {
    let session: Session
    var rowData: SessionRowData?

    var body: some View {
        let isActive = session.isActive
        let messageCount = rowData?.messageCount ?? 0
        let previewContent = rowData?.previewContent
        let isStreaming = rowData?.isStreaming ?? false

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if isActive {
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

                if isActive {
                    Text(L10n.Common.active)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.green))
                }

                Spacer()

                Text(L10n.Sessions.messagesCount(messageCount))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let content = previewContent {
                Text(content)
                    .font(.subheadline)
                    .foregroundStyle(isStreaming ? .primary : .secondary)
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
