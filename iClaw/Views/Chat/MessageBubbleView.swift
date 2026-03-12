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

    private var isAssistant: Bool {
        role == .assistant
    }

    private var toolCalls: [LLMToolCall]? {
        guard let data = message?.toolCallsData else { return nil }
        return try? JSONDecoder().decode([LLMToolCall].self, from: data)
    }

    /// The best copyable text for this message.
    private var copyableText: String {
        if let msg = message {
            if msg.role == .tool {
                return "[\(msg.name ?? "tool")] \(msg.content ?? "")"
            }
            if let calls = toolCalls, !calls.isEmpty {
                var parts: [String] = []
                if let c = msg.content, !c.isEmpty { parts.append(c) }
                for call in calls {
                    parts.append("[\(call.function.name)] \(call.function.arguments)")
                }
                return parts.joined(separator: "\n\n")
            }
            return msg.content ?? ""
        }
        return streamingContent ?? ""
    }

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if isTool {
                    ToolResultCardView(message: message!)
                        .messageContextMenu(text: copyableText)
                } else if let calls = toolCalls, !calls.isEmpty {
                    assistantWithToolCalls(calls)
                        .messageContextMenu(text: copyableText)
                } else {
                    bubbleView
                        .messageContextMenu(text: copyableText)
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

    @ViewBuilder
    private var bubbleView: some View {
        if isUser {
            Text(content)
                .font(.body)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.accentColor)
                )
                .foregroundStyle(.white)
                .textSelection(.enabled)
        } else {
            MarkdownContentView(content, isUser: false)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                )
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func assistantWithToolCalls(_ calls: [LLMToolCall]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !content.isEmpty {
                MarkdownContentView(content, isUser: false)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                    )
                    .foregroundStyle(.primary)
            }

            ToolCallCardView(toolCalls: calls)
        }
    }
}

// MARK: - Context Menu Modifier

private struct MessageContextMenuModifier: ViewModifier {
    let text: String
    @State private var showCopied = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    UIPasteboard.general.string = text
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopied = false
                    }
                } label: {
                    Label(L10n.Common.copy, systemImage: "doc.on.doc")
                }

                if let url = URL(string: text), UIApplication.shared.canOpenURL(url) {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Label(L10n.Chat.openLink, systemImage: "safari")
                    }
                }

                Button {
                    let activityVC = UIActivityViewController(
                        activityItems: [text],
                        applicationActivities: nil
                    )
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController {
                        var topVC = rootVC
                        while let presented = topVC.presentedViewController {
                            topVC = presented
                        }
                        if let popover = activityVC.popoverPresentationController {
                            popover.sourceView = topVC.view
                            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                            popover.permittedArrowDirections = []
                        }
                        topVC.present(activityVC, animated: true)
                    }
                } label: {
                    Label(L10n.Chat.share, systemImage: "square.and.arrow.up")
                }
            }
            .overlay(alignment: .top) {
                if showCopied {
                    Text(L10n.Common.copied)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.7)))
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeOut(duration: 0.2), value: showCopied)
                }
            }
    }
}

extension View {
    func messageContextMenu(text: String) -> some View {
        modifier(MessageContextMenuModifier(text: text))
    }
}
