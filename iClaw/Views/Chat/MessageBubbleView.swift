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

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if isTool {
                    ToolResultCardView(message: message!)
                } else if let calls = toolCalls, !calls.isEmpty {
                    assistantWithToolCalls(calls)
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
