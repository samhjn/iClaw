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

        // Ensure tool call pairs are intact:
        // - A tool message must be preceded by an assistant message with matching tool_calls
        // - An assistant message with tool_calls must be followed by all its tool responses
        selected = repairToolCallPairs(selected)

        return selected
    }

    /// Ensures tool call message pairs are intact.
    /// Removes orphan tool messages at the start (no preceding assistant with tool_calls),
    /// and removes trailing assistant+tool_calls that lack their tool responses.
    private func repairToolCallPairs(_ messages: [Message]) -> [Message] {
        var result = messages

        // Remove orphan tool messages at the beginning
        while let first = result.first, first.role == .tool {
            result.removeFirst()
        }

        // Remove trailing assistant with tool_calls if its tool responses are missing
        if let last = result.last, last.role == .assistant, last.toolCallsData != nil {
            if let toolCalls = try? JSONDecoder().decode([LLMToolCall].self, from: last.toolCallsData!) {
                let expectedIds = Set(toolCalls.map(\.id))
                let followingToolIds = Set(
                    result.dropLast()
                        .suffix(toolCalls.count)
                        .filter { $0.role == .tool }
                        .compactMap(\.toolCallId)
                )
                if !expectedIds.isSubset(of: followingToolIds) {
                    result.removeLast()
                }
            }
        }

        return result
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
