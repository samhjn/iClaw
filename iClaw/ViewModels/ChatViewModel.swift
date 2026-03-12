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

    /// True while a cancel request is being processed.
    var isCancelling: Bool = false

    /// Whether a manual compression is running.
    var isCompressing: Bool = false

    /// The message ID the scroll view should initially restore to.
    var initialScrollTarget: UUID?

    let session: Session
    private var modelContext: ModelContext
    private var generationTask: Task<Void, Never>?
    private var compressionTask: Task<Void, Never>?
    private var monitoringTask: Task<Void, Never>?
    private var cancelled = false

    init(session: Session, modelContext: ModelContext) {
        self.session = session
        self.modelContext = modelContext
        loadMessages()
        checkActiveSessionLock()
        recoverStaleActiveState()
        recoverCompressionState()
        startMonitoringIfNeeded()
        initialScrollTarget = session.lastViewedMessageId
    }

    func loadMessages() {
        messages = session.sortedMessages
    }

    // MARK: - Scroll Position Tracking

    func saveScrollPosition(_ messageId: UUID?) {
        session.lastViewedMessageId = messageId
        try? modelContext.save()
    }

    // MARK: - Active Session Lock

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

    // MARK: - Cancel Generation

    func cancelGeneration() {
        guard isLoading, generationTask != nil else { return }
        isCancelling = true
        cancelled = true
        generationTask?.cancel()
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

        if !session.isTitleCustomized && session.title == "New Chat" {
            let titleText = text.prefix(40)
            session.title = titleText.count < text.count ? "\(titleText)..." : String(titleText)
        }

        try? modelContext.save()
        loadMessages()

        cancelled = false
        generationTask = Task {
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
            isCancelling = false
            session.isActive = false
            generationTask = nil
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
                if Task.isCancelled || cancelled {
                    if !fullContent.isEmpty {
                        let partialMsg = Message(
                            role: .assistant,
                            content: fullContent + "\n\n⚠️ *[已中止]*",
                            session: session
                        )
                        modelContext.insert(partialMsg)
                        session.messages.append(partialMsg)
                        session.updatedAt = Date()
                        try? modelContext.save()
                        loadMessages()
                    }
                    return
                }

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

            if Task.isCancelled || cancelled {
                if !fullContent.isEmpty {
                    let partialMsg = Message(
                        role: .assistant,
                        content: fullContent + "\n\n⚠️ *[已中止]*",
                        session: session
                    )
                    modelContext.insert(partialMsg)
                    session.messages.append(partialMsg)
                    session.updatedAt = Date()
                    try? modelContext.save()
                    loadMessages()
                }
                return
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
            if !Task.isCancelled && !cancelled {
                errorMessage = error.localizedDescription
            }
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
            if Task.isCancelled || cancelled {
                let cancelMsg = Message(
                    role: .assistant,
                    content: "⚠️ *[工具调用已中止]*",
                    session: session
                )
                modelContext.insert(cancelMsg)
                session.messages.append(cancelMsg)
                try? modelContext.save()
                loadMessages()
                return
            }

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

        if Task.isCancelled || cancelled { return }

        await generateResponse()
    }

    @MainActor
    private func checkAndCompress(agent: Agent, router: ModelRouter) async {
        let threshold = agent.effectiveCompressionThreshold
        let compressor = SessionCompressor(compressionThreshold: threshold)
        if compressor.shouldCompress(session: session) {
            guard let provider = router.primaryProvider(for: agent) else { return }
            let llmService = LLMService(provider: provider)
            await compressor.compress(session: session, llmService: llmService, modelContext: modelContext)
            loadMessages()
        }
    }

    // MARK: - Manual Compression

    func manualCompress() {
        guard !isCompressing, compressionTask == nil else { return }
        guard let agent = session.agent else { return }

        isCompressing = true
        session.isCompressingContext = true
        try? modelContext.save()

        compressionTask = Task { @MainActor [weak self] in
            defer {
                self?.isCompressing = false
                self?.session.isCompressingContext = false
                self?.compressionTask = nil
                try? self?.modelContext.save()
            }

            guard let self else { return }

            let router = ModelRouter(modelContext: self.modelContext)
            guard let provider = router.primaryProvider(for: agent) else {
                self.errorMessage = "没有可用的模型来执行压缩"
                return
            }

            let threshold = agent.effectiveCompressionThreshold
            let compressor = SessionCompressor(compressionThreshold: threshold)
            let llmService = LLMService(provider: provider)
            await compressor.compress(session: self.session, llmService: llmService, modelContext: self.modelContext)
            self.loadMessages()
        }
    }

    // MARK: - View Lifecycle

    func onViewAppear() {
        loadMessages()
        checkActiveSessionLock()
        recoverStaleActiveState()
        recoverCompressionState()
        if !session.isActive && generationTask == nil {
            isLoading = false
            streamingContent = ""
        }
        startMonitoringIfNeeded()
    }

    func onViewDisappear() {
        stopMonitoring()
    }

    // MARK: - Stale Active State Recovery

    /// If the session is marked active but no task is running and this is a fresh
    /// ViewModel (app was killed / navigated away for a long time), reset the flag.
    private func recoverStaleActiveState() {
        guard session.isActive, generationTask == nil else { return }

        let lastUpdate = session.updatedAt
        let staleDuration: TimeInterval = 120
        if Date().timeIntervalSince(lastUpdate) > staleDuration {
            session.isActive = false
            try? modelContext.save()
        }
    }

    // MARK: - Compression State Recovery

    /// Recover the UI compression indicator when the persistent flag is set
    /// but this ViewModel doesn't own the task (e.g. view was recreated).
    private func recoverCompressionState() {
        if session.isCompressingContext && compressionTask == nil {
            let staleDuration: TimeInterval = 120
            if Date().timeIntervalSince(session.updatedAt) > staleDuration {
                session.isCompressingContext = false
                try? modelContext.save()
                isCompressing = false
            } else {
                isCompressing = true
                startCompressionMonitoring()
            }
        } else if !session.isCompressingContext {
            isCompressing = false
        }
    }

    /// Poll the persistent flag to track an orphaned compression task.
    private func startCompressionMonitoring() {
        guard compressionTask == nil else { return }
        compressionTask = Task { @MainActor [weak self] in
            defer {
                self?.isCompressing = false
                self?.compressionTask = nil
            }
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if !self.session.isCompressingContext {
                    self.loadMessages()
                    return
                }
                ticks += 1
                if ticks > 120 {
                    self.session.isCompressingContext = false
                    try? self.modelContext.save()
                    return
                }
            }
        }
    }

    // MARK: - Orphaned Loop Monitoring

    private func startMonitoringIfNeeded() {
        guard session.isActive, generationTask == nil, monitoringTask == nil else { return }
        isLoading = true
        monitoringTask = Task { @MainActor [weak self] in
            defer {
                self?.isLoading = false
                self?.loadMessages()
                self?.checkActiveSessionLock()
                self?.monitoringTask = nil
            }

            var tickCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.loadMessages()
                tickCount += 1

                guard self.session.isActive else { return }

                // Safety: if session has been "active" for 5 minutes without
                // updates, treat it as stale and force-reset.
                if tickCount > 300 {
                    self.session.isActive = false
                    try? self.modelContext.save()
                    return
                }
            }
        }
    }

    private func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // MARK: - Manual Title

    func setCustomTitle(_ title: String) {
        session.title = title
        session.isTitleCustomized = true
        session.updatedAt = Date()
        try? modelContext.save()
    }

    // MARK: - Info

    var compressionInfo: String {
        let contextManager = ContextManager()
        let active = contextManager.activeContextTokens(session: session)
        let threshold = session.agent?.effectiveCompressionThreshold ?? ContextManager.compressionThreshold
        let compressed = session.compressedUpToIndex
        let msgCount = session.messages.count

        func fmt(_ n: Int) -> String {
            n >= 1000 ? String(format: "%.1fk", Double(n) / 1000.0) : "\(n)"
        }

        return "上下文 ≈\(fmt(active)) / \(fmt(threshold)) | \(msgCount)条(\(compressed)条已压缩)"
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
