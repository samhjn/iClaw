import Foundation

final class ContextManager {
    static let defaultMaxTokens = 32000
    static let compressionThreshold = 24000

    let maxContextTokens: Int

    init(maxContextTokens: Int = ContextManager.defaultMaxTokens) {
        self.maxContextTokens = maxContextTokens
    }

    func buildContextWindow(
        session: Session,
        systemPrompt: String,
        supportsVision: Bool = false
    ) -> [LLMChatMessage] {
        var messages: [LLMChatMessage] = []

        let hasCompressed = session.compressedUpToIndex > 0
        let compressed = session.compressedContext ?? ""

        var fullSystemPrompt = systemPrompt
        if hasCompressed, !compressed.isEmpty {
            fullSystemPrompt += "\n\n---\n\n"
            fullSystemPrompt += "## Compressed Conversation History\n\n"
            fullSystemPrompt += "**The following is a structured summary of earlier messages. "
            fullSystemPrompt += "The \"Active Directives\" section contains user instructions that are STILL IN EFFECT — "
            fullSystemPrompt += "you MUST continue to follow them as if the user just said them.**\n\n"
            fullSystemPrompt += compressed
        }
        messages.append(.system(fullSystemPrompt))

        let systemTokens = TokenEstimator.estimate(fullSystemPrompt)
        var availableTokens = maxContextTokens - systemTokens

        let sorted = session.sortedMessages.filter { $0.role != .system }

        // When compression has occurred, pin the first user message (original
        // task instruction) so the LLM never loses the user's initial intent.
        if hasCompressed {
            if let firstUserMsg = sorted.first(where: { $0.role == .user }) {
                let anchor = convertToLLMMessage(firstUserMsg, supportsVision: supportsVision)
                let anchorTokens = TokenEstimator.estimateMessage(firstUserMsg)
                messages.append(anchor)
                availableTokens -= anchorTokens
            }
        }

        let recentMessages = selectRecentMessages(
            from: sorted,
            startingAfterIndex: session.compressedUpToIndex,
            maxTokens: availableTokens
        )

        for msg in recentMessages {
            messages.append(convertToLLMMessage(msg, supportsVision: supportsVision))
        }

        return messages
    }

    /// Tokens for ALL messages (including already-compressed ones). Useful for stats.
    func totalSessionTokens(session: Session) -> Int {
        session.messages.reduce(0) { total, msg in
            let est = msg.tokenEstimate
            return total + (est > 0 ? est : TokenEstimator.estimateMessage(msg))
        }
    }

    /// Tokens that would actually be sent to the LLM:
    /// compressed summary + messages after `compressedUpToIndex`.
    func activeContextTokens(session: Session) -> Int {
        var total = 0

        if let compressed = session.compressedContext, !compressed.isEmpty {
            total += TokenEstimator.estimate(compressed)
        }

        let sorted = session.sortedMessages.filter { $0.role != .system }
        let active = sorted.dropFirst(session.compressedUpToIndex)
        for msg in active {
            let est = msg.tokenEstimate
            total += est > 0 ? est : TokenEstimator.estimateMessage(msg)
        }

        return total
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
            let tokens = message.tokenEstimate > 0
                ? message.tokenEstimate
                : TokenEstimator.estimateMessage(message)
            if tokenCount + tokens > maxTokens && !selected.isEmpty {
                break
            }
            selected.insert(message, at: 0)
            tokenCount += tokens
        }

        selected = repairToolCallPairs(selected)

        return selected
    }

    /// Ensures tool call message pairs are intact.
    private func repairToolCallPairs(_ messages: [Message]) -> [Message] {
        var result = messages

        while let first = result.first, first.role == .tool {
            result.removeFirst()
        }

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

    private func convertToLLMMessage(_ message: Message, supportsVision: Bool = false) -> LLMChatMessage {
        switch message.role {
        case .user:
            let text = message.content ?? ""
            if supportsVision, let imgData = message.imageAttachmentsData,
               let images = try? JSONDecoder().decode([ImageAttachment].self, from: imgData),
               !images.isEmpty {
                return .userWithImages(text, images: images)
            }
            return .user(text)
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
}

// MARK: - Token Estimator

/// BPE-aware token estimator for mixed CJK/Latin text.
///
/// Calibrated against GPT-4 / Claude tokenizer behavior:
/// - ASCII text: ~1 token per 4 characters
/// - CJK ideographs: ~2 tokens per character
/// - Hangul syllables: ~2 tokens per character
/// - Emoji / symbols: ~3 tokens each
/// - Whitespace/punctuation grouped with surrounding text
/// - Per-message overhead: ~4 tokens (role tag, delimiters)
enum TokenEstimator {

    static func estimate(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        var asciiCount = 0
        var cjkCount = 0
        var emojiCount = 0

        for scalar in text.unicodeScalars {
            let v = scalar.value
            if v <= 0x7F {
                asciiCount += 1
            } else if isCJK(v) {
                cjkCount += 1
            } else if isEmoji(v) || v > 0xFFFF {
                emojiCount += 1
            } else {
                // Other multi-byte (Cyrillic, Arabic, Thai, extended Latin, etc.)
                // ~2 characters per token on average
                cjkCount += 1
            }
        }

        let asciiTokens = max(asciiCount / 4, asciiCount > 0 ? 1 : 0)
        let cjkTokens = cjkCount * 2
        let emojiTokens = emojiCount * 3

        return asciiTokens + cjkTokens + emojiTokens
    }

    /// Estimate tokens for a Message, including content, tool calls, and overhead.
    static func estimateMessage(_ message: Message) -> Int {
        let overhead = 4
        var total = overhead

        if let content = message.content {
            total += estimate(content)
        }

        if let toolData = message.toolCallsData {
            if let calls = try? JSONDecoder().decode([LLMToolCall].self, from: toolData) {
                for call in calls {
                    total += estimate(call.function.name)
                    total += estimate(call.function.arguments)
                    total += 8 // id, type, structural tokens
                }
            }
        }

        if let name = message.name {
            total += estimate(name) + 1
        }

        return total
    }

    private static func isCJK(_ v: UInt32) -> Bool {
        // CJK Unified Ideographs
        (v >= 0x4E00 && v <= 0x9FFF) ||
        // CJK Extension A
        (v >= 0x3400 && v <= 0x4DBF) ||
        // CJK Extension B-F
        (v >= 0x20000 && v <= 0x2FA1F) ||
        // CJK Compatibility Ideographs
        (v >= 0xF900 && v <= 0xFAFF) ||
        // Hiragana
        (v >= 0x3040 && v <= 0x309F) ||
        // Katakana
        (v >= 0x30A0 && v <= 0x30FF) ||
        // Hangul Syllables
        (v >= 0xAC00 && v <= 0xD7AF) ||
        // CJK Symbols and Punctuation
        (v >= 0x3000 && v <= 0x303F) ||
        // Fullwidth Forms
        (v >= 0xFF00 && v <= 0xFFEF) ||
        // Bopomofo
        (v >= 0x3100 && v <= 0x312F)
    }

    private static func isEmoji(_ v: UInt32) -> Bool {
        (v >= 0x1F600 && v <= 0x1F64F) ||
        (v >= 0x1F300 && v <= 0x1F5FF) ||
        (v >= 0x1F680 && v <= 0x1F6FF) ||
        (v >= 0x1F900 && v <= 0x1F9FF) ||
        (v >= 0x2600 && v <= 0x26FF) ||
        (v >= 0x2700 && v <= 0x27BF) ||
        (v >= 0xFE00 && v <= 0xFE0F) ||
        (v >= 0x1FA00 && v <= 0x1FA6F) ||
        (v >= 0x1FA70 && v <= 0x1FAFF)
    }
}
