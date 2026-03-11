import Foundation

final class ContextManager {
    static let defaultMaxTokens = 8000
    static let compressionThreshold = 6000

    let maxContextTokens: Int

    init(maxContextTokens: Int = ContextManager.defaultMaxTokens) {
        self.maxContextTokens = maxContextTokens
    }

    func buildContextWindow(
        session: Session,
        systemPrompt: String
    ) -> [LLMChatMessage] {
        var messages: [LLMChatMessage] = []

        var fullSystemPrompt = systemPrompt
        if let compressed = session.compressedContext, !compressed.isEmpty {
            fullSystemPrompt += "\n\n---\n\n## Earlier Conversation Summary\n\n\(compressed)"
        }
        messages.append(.system(fullSystemPrompt))

        let systemTokens = estimateTokens(fullSystemPrompt)
        let availableTokens = maxContextTokens - systemTokens

        let sorted = session.sortedMessages.filter { $0.role != .system }

        let recentMessages = selectRecentMessages(
            from: sorted,
            startingAfterIndex: session.compressedUpToIndex,
            maxTokens: availableTokens
        )

        for msg in recentMessages {
            messages.append(convertToLLMMessage(msg))
        }

        return messages
    }

    func totalSessionTokens(session: Session) -> Int {
        session.messages.reduce(0) { $0 + $1.tokenEstimate }
    }

    private func selectRecentMessages(
        from messages: [Message],
        startingAfterIndex: Int,
        maxTokens: Int
    ) -> [Message] {
        let eligible = Array(messages.dropFirst(startingAfterIndex))

        var selected: [Message] = []
        var tokenCount = 0

        for message in eligible.reversed() {
            let tokens = message.tokenEstimate > 0 ? message.tokenEstimate : estimateTokens(message.content ?? "")
            if tokenCount + tokens > maxTokens && !selected.isEmpty {
                break
            }
            selected.insert(message, at: 0)
            tokenCount += tokens
        }

        return selected
    }

    private func convertToLLMMessage(_ message: Message) -> LLMChatMessage {
        switch message.role {
        case .user:
            return .user(message.content ?? "")
        case .assistant:
            var toolCalls: [LLMToolCall]? = nil
            if let data = message.toolCallsData {
                toolCalls = try? JSONDecoder().decode([LLMToolCall].self, from: data)
            }
            return .assistant(message.content, toolCalls: toolCalls)
        case .tool:
            return .tool(
                content: message.content ?? "",
                toolCallId: message.toolCallId ?? "",
                name: message.name
            )
        case .system:
            return .system(message.content ?? "")
        }
    }

    func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }
}
