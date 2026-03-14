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

    /// If cancel fails or takes too long, explains why.
    var cancelFailureReason: String?

    /// Whether a manual compression is running.
    var isCompressing: Bool = false

    /// True while a compression cancel is being processed.
    var isCancellingCompression: Bool = false

    /// The message ID the scroll view should initially restore to.
    var initialScrollTarget: UUID?

    let session: Session
    private var modelContext: ModelContext
    private var generationTask: Task<Void, Never>?
    /// The actual compression work task — should NOT be cancelled on view disappear.
    private var compressionTask: Task<Void, Never>?
    /// A lightweight polling task that tracks an orphaned compression (started by a previous ViewModel).
    private var compressionMonitorTask: Task<Void, Never>?
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
            sendBlockedReason = L10n.Chat.sessionBlocked(blocking.title)
        } else {
            sendBlockedReason = nil
        }
    }

    var canSend: Bool {
        sendBlockedReason == nil
    }

    // MARK: - Cancel Generation

    private var cancelWatchdog: Task<Void, Never>?

    func cancelGeneration() {
        guard isLoading, generationTask != nil else { return }
        isCancelling = true
        cancelFailureReason = nil
        cancelled = true
        generationTask?.cancel()

        cancelWatchdog?.cancel()
        cancelWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled, self.isCancelling, self.isLoading else { return }
            self.cancelFailureReason = L10n.Chat.cancelStuckReason

            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, self.isCancelling, self.isLoading else { return }
            self.forceStopGeneration()
        }
    }

    @MainActor
    private func forceStopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isLoading = false
        isCancelling = false
        session.isActive = false
        session.pendingStreamingContent = nil
        cancelFailureReason = nil
        cancelWatchdog?.cancel()
        cancelWatchdog = nil
        BrowserService.shared.releaseLock(sessionId: session.id)

        let forceStopMsg = Message(
            role: .assistant,
            content: L10n.Chat.forceStoppedContent,
            session: session
        )
        modelContext.insert(forceStopMsg)
        session.messages.append(forceStopMsg)
        session.updatedAt = Date()
        try? modelContext.save()
        loadMessages()
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

        if !session.isTitleCustomized && session.title == L10n.Chat.newChat {
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

    private var generationDepth = 0

    @MainActor
    func generateResponse() async {
        let isTopLevel = generationDepth == 0
        generationDepth += 1

        if isTopLevel {
            isLoading = true
            streamingContent = ""
            errorMessage = nil
            session.isActive = true
            try? modelContext.save()
        } else {
            streamingContent = ""
        }

        defer {
            generationDepth -= 1
            if generationDepth == 0 {
                isLoading = false
                streamingContent = ""
                isCancelling = false
                cancelFailureReason = nil
                cancelWatchdog?.cancel()
                cancelWatchdog = nil
                session.isActive = false
                session.pendingStreamingContent = nil
                generationTask = nil
                try? modelContext.save()
                BrowserService.shared.releaseLock(sessionId: session.id)
            }
        }

        guard let agent = session.agent else {
            errorMessage = L10n.Chat.noAgent
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

            var lastPersistTime = Date()

            for await chunk in stream {
                if Task.isCancelled || cancelled {
                    if !fullContent.isEmpty {
                        let partialMsg = Message(
                            role: .assistant,
                            content: fullContent + L10n.Chat.aborted,
                            session: session
                        )
                        modelContext.insert(partialMsg)
                        session.messages.append(partialMsg)
                        session.updatedAt = Date()
                        session.pendingStreamingContent = nil
                        try? modelContext.save()
                        loadMessages()
                    }
                    return
                }

                switch chunk {
                case .content(let text):
                    fullContent += text
                    streamingContent = fullContent
                    let now = Date()
                    if now.timeIntervalSince(lastPersistTime) >= 1.0 {
                        session.pendingStreamingContent = fullContent
                        session.updatedAt = now
                        try? modelContext.save()
                        lastPersistTime = now
                    }
                case .toolCall(let toolCall):
                    pendingToolCalls.append(toolCall)
                case .done:
                    break
                case .error(let error):
                    errorMessage = error
                    return
                }
            }

            session.pendingStreamingContent = nil

            if Task.isCancelled || cancelled {
                if !fullContent.isEmpty {
                    let partialMsg = Message(
                        role: .assistant,
                        content: fullContent + L10n.Chat.aborted,
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
        let fnRouter = FunctionCallRouter(agent: agent, modelContext: modelContext, sessionId: session.id)

        for toolCall in toolCalls {
            if Task.isCancelled || cancelled {
                let cancelMsg = Message(
                    role: .assistant,
                    content: L10n.Chat.toolCallAborted,
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
        guard !Task.isCancelled, !cancelled else { return }
        let threshold = agent.effectiveCompressionThreshold
        let compressor = SessionCompressor(compressionThreshold: threshold)
        if compressor.shouldCompress(session: session) {
            isCompressing = true
            session.isCompressingContext = true
            try? modelContext.save()
            defer {
                isCompressing = false
                session.isCompressingContext = false
                try? modelContext.save()
            }
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
        isCancellingCompression = false
        session.isCompressingContext = true
        try? modelContext.save()

        let session = self.session
        let modelContext = self.modelContext

        compressionTask = Task { @MainActor [weak self] in
            defer {
                self?.isCompressing = false
                self?.isCancellingCompression = false
                session.isCompressingContext = false
                self?.compressionTask = nil
                try? modelContext.save()
            }

            guard let self else { return }

            let router = ModelRouter(modelContext: modelContext)
            guard let provider = router.primaryProvider(for: agent) else {
                self.errorMessage = L10n.Chat.noCompressModel
                return
            }

            let threshold = agent.effectiveCompressionThreshold
            let compressor = SessionCompressor(compressionThreshold: threshold)
            let llmService = LLMService(provider: provider)
            await compressor.compress(session: session, llmService: llmService, modelContext: modelContext)
            self.loadMessages()
        }
    }

    func cancelCompression() {
        guard isCompressing else { return }
        isCancellingCompression = true
        compressionTask?.cancel()
        compressionTask = nil
        compressionMonitorTask?.cancel()
        compressionMonitorTask = nil
        isCompressing = false
        isCancellingCompression = false
        session.isCompressingContext = false
        try? modelContext.save()
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
        compressionMonitorTask?.cancel()
        compressionMonitorTask = nil
        isCompressing = false
        cancelWatchdog?.cancel()
        cancelWatchdog = nil
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
            session.pendingStreamingContent = nil
            try? modelContext.save()
            let sessionId = session.id
            Task { @MainActor in
                BrowserService.shared.releaseLock(sessionId: sessionId)
            }
        }
    }

    // MARK: - Compression State Recovery

    /// Recover the UI compression indicator when the persistent flag is set
    /// but this ViewModel doesn't own the task (e.g. view was recreated).
    private func recoverCompressionState() {
        if session.isCompressingContext {
            if compressionTask != nil {
                // We own the real task — just restore the UI flag.
                isCompressing = true
            } else {
                // We don't own the task; either it's running from a previous
                // ViewModel instance, or it's stale.
                let staleDuration: TimeInterval = 120
                if Date().timeIntervalSince(session.updatedAt) > staleDuration {
                    session.isCompressingContext = false
                    try? modelContext.save()
                    isCompressing = false
                } else {
                    isCompressing = true
                    startCompressionMonitoring()
                }
            }
        } else {
            isCompressing = false
        }
    }

    /// Poll the persistent flag to track an orphaned compression task.
    private func startCompressionMonitoring() {
        guard compressionMonitorTask == nil else { return }
        let session = self.session
        let modelContext = self.modelContext
        compressionMonitorTask = Task { @MainActor [weak self] in
            defer {
                self?.isCompressing = false
                self?.compressionMonitorTask = nil
            }
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if !session.isCompressingContext {
                    self?.loadMessages()
                    return
                }
                // If the session is no longer active and compression flag is stale,
                // the orphaned task likely finished but failed to clear the flag.
                if !session.isActive && ticks > 5 {
                    session.isCompressingContext = false
                    try? modelContext.save()
                    self?.loadMessages()
                    return
                }
                ticks += 1
                if ticks > 120 {
                    session.isCompressingContext = false
                    try? modelContext.save()
                    return
                }
            }
        }
    }

    // MARK: - Orphaned Loop Monitoring

    private func startMonitoringIfNeeded() {
        guard session.isActive, generationTask == nil, monitoringTask == nil else { return }
        isLoading = true

        if let pending = session.pendingStreamingContent, !pending.isEmpty {
            streamingContent = pending
        }

        monitoringTask = Task { @MainActor [weak self] in
            defer {
                self?.isLoading = false
                self?.streamingContent = ""
                if let self, !self.session.isCompressingContext {
                    self.isCompressing = false
                }
                self?.loadMessages()
                self?.checkActiveSessionLock()
                self?.monitoringTask = nil
            }

            var tickCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.loadMessages()

                if let pending = self.session.pendingStreamingContent, !pending.isEmpty {
                    self.streamingContent = pending
                }

                if !self.session.isCompressingContext && self.isCompressing && self.compressionTask == nil {
                    self.isCompressing = false
                }

                tickCount += 1

                guard self.session.isActive else { return }

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

        return L10n.Chat.compressionInfo(active: fmt(active), threshold: fmt(threshold), total: msgCount, compressed: compressed)
    }
}

enum ChatError: LocalizedError {
    case noProviderConfigured
    case noAgentAssociated

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured:
            return L10n.ChatError.noProvider
        case .noAgentAssociated:
            return L10n.ChatError.noAgent
        }
    }
}
