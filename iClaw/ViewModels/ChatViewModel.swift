import Foundation
import SwiftData
import Observation

@Observable
final class ChatViewModel {
    var messages: [Message] = []
    var inputText: String = ""
    var isLoading: Bool = false
    var streamingContent: String = ""
    var errorMessage: String?
    var activeModelName: String?

    /// If another session of the same agent is active, this holds the blocking reason.
    var sendBlockedReason: String?

    let session: Session
    private var modelContext: ModelContext

    init(session: Session, modelContext: ModelContext) {
        self.session = session
        self.modelContext = modelContext
        loadMessages()
        checkActiveSessionLock()
    }

    func loadMessages() {
        messages = session.sortedMessages
    }

    // MARK: - Active Session Lock

    /// Check if another session of the same agent is currently active.
    func checkActiveSessionLock() {
        guard let agent = session.agent else {
            sendBlockedReason = nil
            return
        }

        let otherActive = agent.sessions.first { s in
            s.id != session.id && s.isActive
        }

        if let blocking = otherActive {
            sendBlockedReason = "「\(blocking.title)」正在处理中，同一 Agent 同时只允许一个活跃 Session。"
        } else {
            sendBlockedReason = nil
        }
    }

    var canSend: Bool {
        sendBlockedReason == nil
    }

    // MARK: - Send Message

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        checkActiveSessionLock()
        guard canSend else { return }

        inputText = ""

        let userMessage = Message(role: .user, content: text, session: session)
        modelContext.insert(userMessage)
        session.messages.append(userMessage)
        session.updatedAt = Date()

        // Auto-title from first user message
        if !session.isTitleCustomized && session.title == "New Chat" {
            let titleText = text.prefix(40)
            session.title = titleText.count < text.count ? "\(titleText)..." : String(titleText)
        }

        try? modelContext.save()
        loadMessages()

        Task {
            await generateResponse()
        }
    }

    @MainActor
    func generateResponse() async {
        isLoading = true
        streamingContent = ""
        errorMessage = nil
        session.isActive = true
        try? modelContext.save()

        defer {
            isLoading = false
            streamingContent = ""
            session.isActive = false
            try? modelContext.save()
        }

        guard let agent = session.agent else {
            errorMessage = "No agent associated with this session"
            return
        }

        do {
            let router = ModelRouter(modelContext: modelContext)
            let promptBuilder = PromptBuilder()
            let contextManager = ContextManager()

            let systemPrompt = promptBuilder.buildSystemPrompt(for: agent, isSubAgent: agent.parentAgent != nil)
            let contextMessages = contextManager.buildContextWindow(
                session: session,
                systemPrompt: systemPrompt
            )

            let toolDefs = ToolDefinitions.allTools

            var fullContent = ""
            var pendingToolCalls: [LLMToolCall] = []

            let (stream, providerName) = try await router.chatCompletionStreamWithFailover(
                agent: agent,
                messages: contextMessages,
                tools: toolDefs
            )
            activeModelName = providerName

            for await chunk in stream {
                switch chunk {
                case .content(let text):
                    fullContent += text
                    streamingContent = fullContent
                case .toolCall(let toolCall):
                    pendingToolCalls.append(toolCall)
                case .done:
                    break
                case .error(let error):
                    errorMessage = error
                    return
                }
            }

            if !pendingToolCalls.isEmpty {
                let assistantMsg = Message(
                    role: .assistant,
                    content: fullContent.isEmpty ? nil : fullContent,
                    toolCallsData: try? JSONEncoder().encode(pendingToolCalls),
                    session: session
                )
                modelContext.insert(assistantMsg)
                session.messages.append(assistantMsg)
                try? modelContext.save()
                loadMessages()

                await processToolCalls(pendingToolCalls, router: router, agent: agent)
            } else if !fullContent.isEmpty {
                let assistantMsg = Message(role: .assistant, content: fullContent, session: session)
                modelContext.insert(assistantMsg)
                session.messages.append(assistantMsg)
                session.updatedAt = Date()
                try? modelContext.save()
                loadMessages()
            }

            await checkAndCompress(agent: agent, router: router)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func processToolCalls(
        _ toolCalls: [LLMToolCall],
        router: ModelRouter,
        agent: Agent
    ) async {
        let fnRouter = FunctionCallRouter(agent: agent, modelContext: modelContext)

        for toolCall in toolCalls {
            let result = await fnRouter.execute(toolCall: toolCall)
            let toolMsg = Message(
                role: .tool,
                content: result,
                toolCallId: toolCall.id,
                name: toolCall.function.name,
                session: session
            )
            modelContext.insert(toolMsg)
            session.messages.append(toolMsg)
        }

        try? modelContext.save()
        loadMessages()

        await generateResponse()
    }

    @MainActor
    private func checkAndCompress(agent: Agent, router: ModelRouter) async {
        let compressor = SessionCompressor()
        if compressor.shouldCompress(session: session) {
            guard let provider = router.primaryProvider(for: agent) else { return }
            let llmService = LLMService(provider: provider)
            await compressor.compress(session: session, llmService: llmService, modelContext: modelContext)
            loadMessages()
        }
    }

    // MARK: - Manual Title

    func setCustomTitle(_ title: String) {
        session.title = title
        session.isTitleCustomized = true
        session.updatedAt = Date()
        try? modelContext.save()
    }
}

enum ChatError: LocalizedError {
    case noProviderConfigured
    case noAgentAssociated

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured:
            return "No LLM provider configured. Please add one in Settings."
        case .noAgentAssociated:
            return "No agent associated with this session."
        }
    }
}
