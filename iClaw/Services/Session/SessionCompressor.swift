import Foundation
import SwiftData

final class SessionCompressor {
    let compressionThreshold: Int

    init(compressionThreshold: Int = ContextManager.compressionThreshold) {
        self.compressionThreshold = compressionThreshold
    }

    func shouldCompress(session: Session) -> Bool {
        let contextManager = ContextManager()
        let active = contextManager.activeContextTokens(session: session)
        return active > compressionThreshold
    }

    @MainActor
    func compress(
        session: Session,
        llmService: LLMService,
        modelContext: ModelContext
    ) async {
        let sorted = session.sortedMessages
        let startIdx = session.compressedUpToIndex
        let totalMessages = sorted.count

        guard totalMessages > startIdx + 4 else { return }

        let endIdx = totalMessages - 3
        guard endIdx > startIdx else { return }

        let messagesToCompress = Array(sorted[startIdx..<endIdx])
        let transcript = formatTranscript(messagesToCompress)

        let compressionPrompt = """
        You are a conversation summarizer. Compress the following conversation transcript into a concise but comprehensive summary. \
        Preserve key decisions, facts, user preferences, code context, and important outcomes. \
        Be factual and structured. Use bullet points for clarity.

        Transcript:
        \(transcript)
        """

        do {
            let messages: [LLMChatMessage] = [
                .system("You summarize conversations concisely."),
                .user(compressionPrompt)
            ]

            let response = try await llmService.chatCompletion(messages: messages)

            if let summary = response.choices.first?.message?.content {
                let existingContext = session.compressedContext ?? ""
                if existingContext.isEmpty {
                    session.compressedContext = summary
                } else {
                    session.compressedContext = existingContext + "\n\n---\n\n" + summary
                }
                session.compressedUpToIndex = endIdx
                session.updatedAt = Date()
                try? modelContext.save()
            }

            // Auto-generate title when compressing if user hasn't customized it
            if !session.isTitleCustomized {
                await generateTitle(for: session, llmService: llmService, modelContext: modelContext)
            }
        } catch {
            print("[SessionCompressor] Compression failed: \(error)")
        }
    }

    @MainActor
    private func generateTitle(
        for session: Session,
        llmService: LLMService,
        modelContext: ModelContext
    ) async {
        let recentContent = session.sortedMessages
            .filter { $0.role == .user || $0.role == .assistant }
            .prefix(8)
            .compactMap { $0.content }
            .joined(separator: "\n")

        guard !recentContent.isEmpty else { return }

        let messages: [LLMChatMessage] = [
            .system("Generate a concise title (max 6 words) summarizing this conversation. Reply with only the title, nothing else. No quotes."),
            .user(recentContent)
        ]

        do {
            let response = try await llmService.chatCompletion(messages: messages)
            if let title = response.choices.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                let cleanTitle = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                session.title = String(cleanTitle.prefix(50))
                session.updatedAt = Date()
                try? modelContext.save()
            }
        } catch {
            // Title generation is best-effort
        }
    }

    private func formatTranscript(_ messages: [Message]) -> String {
        messages.compactMap { msg in
            let role = msg.role.rawValue.capitalized
            let content = msg.content ?? "(no content)"
            return "[\(role)] \(content)"
        }.joined(separator: "\n\n")
    }
}
