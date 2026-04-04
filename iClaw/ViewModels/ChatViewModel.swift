import Foundation
import SwiftData
import Observation
import UIKit

@Observable
final class ChatViewModel {
    var messages: [Message] = []
    var inputText: String = "" {
        didSet {
            Self.cachedInputTexts[session.id] = inputText
            // Persist eagerly so draft survives app kill.
            let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            session.draftText = trimmed.isEmpty ? nil : inputText
        }
    }
    var isLoading: Bool = false
    var streamingContent: String = ""
    var streamingThinking: String = ""
    var pendingImages: [ImageAttachment] = []
    var errorMessage: String? {
        didSet {
            if let errorMessage {
                Self.cachedErrors[session.id] = errorMessage
            } else {
                Self.cachedErrors.removeValue(forKey: session.id)
            }
        }
    }
    var activeModelName: String?

    /// True when the last generation ended with an error or was cancelled,
    /// allowing the user to retry without typing a new message.
    var canRetry: Bool = false

    /// If another session of the same agent is active, this holds the blocking reason.
    var sendBlockedReason: String?

    /// True while a cancel request is being processed.
    var isCancelling: Bool = false

    /// If cancel fails or takes too long, explains why.
    var cancelFailureReason: String?

    /// Shown when images or other modalities were stripped for the current model.
    var modalityWarning: String?

    /// Shown when the primary model does not support tool use (function calling).
    var toolUseWarning: String?

    /// Display mode: verbose (show CoT & tool calls) or silent (hide them). Synced to Agent.
    var isVerbose: Bool = true {
        didSet { session.agent?.isVerbose = isVerbose }
    }

    /// Cached from session.agent so ChatContentView.body doesn't observe
    /// SwiftData model properties directly (prevents save-cascade invalidation).
    private(set) var isImageInputDisabled: Bool = false
    private(set) var agentDisplayName: String?

    /// Silent-mode status — survives ViewModel recreation (SwiftData can recreate the VM mid-generation).
    private static var silentStatuses: [UUID: String] = [:]
    private static var silentRounds: [UUID: Int] = [:]
    /// Last tool that was executed, shown alongside thinking status so brief tool calls aren't missed.
    private static var silentLastTools: [UUID: String] = [:]

    var silentStatus: String {
        get { Self.silentStatuses[session.id] ?? "" }
        set { Self.silentStatuses[session.id] = newValue }
    }
    private var silentRound: Int {
        get { Self.silentRounds[session.id] ?? 0 }
        set { Self.silentRounds[session.id] = newValue }
    }
    var silentLastTool: String? {
        Self.silentLastTools[session.id]
    }


    /// Whether a manual compression is running.
    var isCompressing: Bool = false

    /// True while a compression cancel is being processed.
    var isCancellingCompression: Bool = false

    /// The message ID the scroll view should initially restore to.
    var initialScrollTarget: UUID?

    let session: Session
    private var modelContext: ModelContext

    private var agentId: UUID? {
        session.agent.map { AgentFileManager.shared.resolveAgentId(for: $0) }
    }
    private var generationTask: Task<Void, Never>?
    /// Explicit cancel closure for the active SSE stream, bypassing cooperative cancellation.
    private var streamCancelAction: (@Sendable () -> Void)?
    /// The actual compression work task — should NOT be cancelled on view disappear.
    private var compressionTask: Task<Void, Never>?
    /// A lightweight polling task that tracks an orphaned compression (started by a previous ViewModel).
    private var compressionMonitorTask: Task<Void, Never>?
    private var monitoringTask: Task<Void, Never>?
    private var cancelled = false
    /// Images returned by tool calls (e.g. from sub-agents) to be attached
    /// to the next final assistant message for display in the chat UI.
    private var pendingToolImageAttachments: [ImageAttachment] = []

    /// Survives ViewModel recreation caused by SwiftData-triggered view re-renders.
    private static var cachedErrors: [UUID: String] = [:]
    /// Draft input text — survives ViewModel recreation (e.g. silent-mode toggle, navigation).
    private static var cachedInputTexts: [UUID: String] = [:]

    /// Draft pending images — survives ViewModel recreation.
    private static var cachedPendingImages: [UUID: [ImageAttachment]] = [:]

    /// Return cached pending images for a session (used by file browser to exclude draft files).
    static func cachedPendingImages(for sessionId: UUID) -> [ImageAttachment] {
        cachedPendingImages[sessionId] ?? []
    }

    /// Check whether there is a non-empty cached draft for a session (used by session list).
    static func hasCachedInput(for sessionId: UUID) -> Bool {
        if let text = cachedInputTexts[sessionId], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let images = cachedPendingImages[sessionId], !images.isEmpty {
            return true
        }
        return false
    }
    /// Sessions where the user explicitly dismissed the retry/error banner.
    private static var dismissedSessions: Set<UUID> = []
    /// Active generation tasks keyed by session ID — survives ViewModel recreation
    /// so a new ViewModel instance can still cancel an orphaned generation.
    private static var activeGenerations: [UUID: Task<Void, Never>] = [:]
    /// Explicit stream-cancel closures keyed by session ID — survives ViewModel recreation.
    private static var activeStreamCancels: [UUID: @Sendable () -> Void] = [:]

    init(session: Session, modelContext: ModelContext) {
        self.session = session
        self.modelContext = modelContext
        self.isVerbose = session.agent?.isVerbose ?? true
        self.isImageInputDisabled = session.agent.map { $0.permissionLevel(for: .files) == .disabled } ?? false
        self.agentDisplayName = session.agent?.name
        // Restore draft text: prefer in-memory cache (more up-to-date), fall back to persisted value.
        if let cached = Self.cachedInputTexts[session.id], !cached.isEmpty {
            self.inputText = cached
        } else if let draft = session.draftText, !draft.isEmpty {
            self.inputText = draft
            Self.cachedInputTexts[session.id] = draft
        }
        // Restore draft images.
        if let cached = Self.cachedPendingImages[session.id], !cached.isEmpty {
            self.pendingImages = cached
        } else if let data = session.draftImagesData,
                  let images = try? JSONDecoder().decode([ImageAttachment].self, from: data), !images.isEmpty {
            self.pendingImages = images
            Self.cachedPendingImages[session.id] = images
        }
        loadMessages()
        checkActiveSessionLock()
        recoverStaleActiveState()
        recoverCompressionState()
        recoverRetryState()
        recoverActiveModelName()
        startMonitoringIfNeeded()
        checkToolUseCapability()
        initialScrollTarget = session.lastViewedMessageId
    }

    func loadMessages() {
        messages = session.sortedMessages
        migrateInlineImages()
        refreshCompressionStats()
    }

    /// One-time migration: extract inline base64 images from existing assistant messages
    /// into the unified `imageAttachmentsData` storage.
    private func migrateInlineImages() {
        var needsSave = false
        for msg in messages where msg.role == .assistant {
            if msg.extractAndStoreInlineImages(agentId: agentId) {
                needsSave = true
            }
        }
        if needsSave {
            try? modelContext.save()
        }
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

    // MARK: - Tool Use Capability Check

    func checkToolUseCapability() {
        guard let agent = session.agent else {
            toolUseWarning = nil
            return
        }
        let router = ModelRouter(modelContext: modelContext)
        let chain = router.resolveProviderChainWithModels(for: agent)
        guard let primary = chain.first else {
            toolUseWarning = nil
            return
        }
        let effectiveModel = primary.modelName ?? primary.provider.modelName
        let caps = primary.provider.capabilities(for: effectiveModel)
        if !caps.supportsToolUse {
            toolUseWarning = L10n.Chat.toolUseUnsupported(effectiveModel)
        } else {
            toolUseWarning = nil
        }
    }

    // MARK: - Cancel Generation

    private var cancelWatchdog: Task<Void, Never>?

    func cancelGeneration() {
        guard isLoading else { return }
        let localTask = generationTask
        let staticTask = Self.activeGenerations[session.id]
        guard localTask != nil || staticTask != nil else { return }

        isCancelling = true
        cancelFailureReason = nil
        cancelled = true
        canRetry = true

        streamCancelAction?()
        Self.activeStreamCancels[session.id]?()
        streamCancelAction = nil
        Self.activeStreamCancels.removeValue(forKey: session.id)

        localTask?.cancel()
        if localTask == nil { staticTask?.cancel() }
        Self.activeGenerations.removeValue(forKey: session.id)

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
        streamCancelAction?()
        Self.activeStreamCancels[session.id]?()
        streamCancelAction = nil
        Self.activeStreamCancels.removeValue(forKey: session.id)
        generationTask?.cancel()
        Self.activeGenerations[session.id]?.cancel()
        generationTask = nil
        Self.activeGenerations.removeValue(forKey: session.id)
        isLoading = false
        isCancelling = false
        isCompressing = false
        session.isActive = false
        session.isCompressingContext = false
        session.pendingStreamingContent = nil
        cancelFailureReason = nil
        cancelWatchdog?.cancel()
        cancelWatchdog = nil
        compressionTask?.cancel()
        compressionTask = nil
        compressionMonitorTask?.cancel()
        compressionMonitorTask = nil
        BrowserService.shared.releaseLock(sessionId: session.id)

        let forceStopMsg = Message(
            role: .assistant,
            content: L10n.Chat.forceStoppedContent,
            session: session
        )
        modelContext.insert(forceStopMsg)
        session.messages.append(forceStopMsg)
        session.updatedAt = Date()
        canRetry = true
        try? modelContext.save()
        loadMessages()
    }

    // MARK: - Retry Generation

    /// Dismiss both error and natural retry banners persistently.
    func dismissRetry() {
        errorMessage = nil
        canRetry = false
        Self.dismissedSessions.insert(session.id)
    }

    /// Retry the last generation attempt. Works after API errors or user-initiated cancellation.
    func retryGeneration() {
        guard !isLoading else { return }

        checkActiveSessionLock()
        guard canSend else { return }

        isLoading = true
        Self.dismissedSessions.remove(session.id)
        errorMessage = nil
        canRetry = false
        cancelled = false
        silentRound = 1
        silentStatus = "think:1"

        removeTrailingAbortedMessages()

        let task = Task { await generateResponse() }
        generationTask = task
        Self.activeGenerations[session.id] = task
    }

    /// Strips partial/aborted assistant messages from the tail of the session
    /// so a retry doesn't feed broken context to the model.
    private func removeTrailingAbortedMessages() {
        let sorted = session.sortedMessages
        var toRemove: [Message] = []
        for msg in sorted.reversed() {
            if msg.role == .user { break }
            if msg.role == .assistant,
               let content = msg.content,
               (content.contains(L10n.Chat.aborted) || content.contains(L10n.Chat.forceStoppedContent)) {
                toRemove.append(msg)
            } else {
                break
            }
        }
        for msg in toRemove {
            session.messages.removeAll { $0.id == msg.id }
            modelContext.delete(msg)
        }
        if !toRemove.isEmpty {
            try? modelContext.save()
            loadMessages()
        }
    }

    // MARK: - Send Message

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isLoading else { return }

        checkActiveSessionLock()
        guard canSend else { return }

        isLoading = true
        inputText = ""
        session.draftText = nil
        Self.dismissedSessions.remove(session.id)
        canRetry = false
        errorMessage = nil
        silentRound = 1
        silentStatus = "think:1"

        // Promote inline draft images to file-backed attachments now that the message is being sent.
        let finalImages: [ImageAttachment] = pendingImages.compactMap { attachment in
            if attachment.fileReference != nil { return attachment }
            guard let agent = session.agent else { return attachment }
            let aid = AgentFileManager.shared.resolveAgentId(for: agent)
            guard let image = attachment.uiImage else { return attachment }
            return ImageAttachment.from(image: image, agentId: aid) ?? attachment
        }
        let imageData: Data? = finalImages.isEmpty ? nil : try? JSONEncoder().encode(finalImages)
        pendingImages = []
        Self.cachedPendingImages.removeValue(forKey: session.id)
        session.draftImagesData = nil

        let userMessage = Message(role: .user, content: text, session: session)
        userMessage.imageAttachmentsData = imageData
        if imageData != nil { userMessage.recalculateTokenEstimate() }
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
        let task = Task { await generateResponse() }
        generationTask = task
        Self.activeGenerations[session.id] = task
    }

    private var generationDepth = 0

    @MainActor
    func generateResponse() async {
        let isTopLevel = generationDepth == 0
        generationDepth += 1

        if isTopLevel {
            isLoading = true
            streamingContent = ""
            streamingThinking = ""
            errorMessage = nil
            canRetry = false
            session.isActive = true
            try? modelContext.save()
        } else {
            silentRound += 1
            silentStatus = "think:\(silentRound)"
            streamingContent = ""
            streamingThinking = ""
        }

        defer {
            generationDepth -= 1
            if generationDepth == 0 {
                isLoading = false
                streamingContent = ""
                streamingThinking = ""
                isCancelling = false
                cancelFailureReason = nil
                cancelWatchdog?.cancel()
                cancelWatchdog = nil
                streamCancelAction = nil
                Self.activeGenerations.removeValue(forKey: session.id)
                Self.activeStreamCancels.removeValue(forKey: session.id)
                Self.silentStatuses.removeValue(forKey: session.id)
                Self.silentRounds.removeValue(forKey: session.id)
                Self.silentLastTools.removeValue(forKey: session.id)
                session.isActive = false
                session.pendingStreamingContent = nil
                generationTask = nil
                if cancelled || Task.isCancelled {
                    canRetry = true
                }
                try? modelContext.save()
                BrowserService.shared.releaseLock(sessionId: session.id)

                // Update embedding after generation completes (handles continued sessions)
                SessionVectorStore(modelContext: modelContext)
                    .updateEmbedding(for: session)
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

            // Compress BEFORE building context so the LLM always gets a
            // right-sized window instead of a bloated or empty one.
            await compressIfNeeded(agent: agent, router: router)

            guard !Task.isCancelled, !cancelled else { return }

            // Compute related sessions once at session start (first generation)
            // and persist them so the system prompt stays stable across turns.
            let relatedSessions: [(id: UUID, title: String, updatedAt: Date)]
            if agent.permissionLevel(for: .sessions) != .disabled {
                relatedSessions = Self.resolveRelatedSessions(
                    session: session,
                    modelContext: modelContext
                )
            } else {
                relatedSessions = []
            }

            let systemPrompt = promptBuilder.buildSystemPrompt(
                for: agent,
                isSubAgent: agent.parentAgent != nil,
                relatedSessions: relatedSessions
            )
            var contextMessages = contextManager.buildContextWindow(
                session: session,
                systemPrompt: systemPrompt
            )

            let chain = router.resolveProviderChainWithModels(for: agent)
            if let primary = chain.first {
                let effectiveModel = primary.modelName ?? primary.provider.modelName
                let caps = primary.provider.capabilities(for: effectiveModel)
                let strippedCount = Self.stripUnsupportedModalities(from: &contextMessages, capabilities: caps)
                if strippedCount > 0 {
                    modalityWarning = L10n.Chat.modalityStripped(strippedCount, effectiveModel)
                } else {
                    modalityWarning = nil
                }
                if !caps.supportsToolUse {
                    toolUseWarning = L10n.Chat.toolUseUnsupported(effectiveModel)
                } else {
                    toolUseWarning = nil
                }
            }

            let toolDefs = ToolDefinitions.tools(for: agent)

            var fullContent = ""
            var fullThinking = ""
            var pendingToolCalls: [LLMToolCall] = []
            var lastUsage: LLMUsage?

            let (stream, providerName, _, cancelStream) = try await router.chatCompletionStreamWithFailover(
                agent: agent,
                messages: contextMessages,
                tools: toolDefs
            )
            streamCancelAction = cancelStream
            Self.activeStreamCancels[session.id] = cancelStream
            activeModelName = providerName

            var lastPersistTime = Date.distantPast

            for await chunk in stream {
            if Task.isCancelled || cancelled {
                if !fullContent.isEmpty || !pendingToolImageAttachments.isEmpty {
                    let partialMsg = Message(
                        role: .assistant,
                        content: fullContent.isEmpty ? nil : fullContent + L10n.Chat.aborted,
                        session: session
                    )
                    partialMsg.extractAndStoreInlineImages(agentId: agentId)
                    attachPendingToolImages(to: partialMsg)
                    modelContext.insert(partialMsg)
                    session.messages.append(partialMsg)
                    session.updatedAt = Date()
                    session.pendingStreamingContent = nil
                    try? modelContext.save()
                    loadMessages()
                }
                canRetry = true
                return
            }

                switch chunk {
                case .thinking(let text):
                    fullThinking += text
                    streamingThinking = fullThinking
                case .content(let text):
                    fullContent += text
                    streamingContent = fullContent
                    let now = Date()
                    let isFirstChunk = lastPersistTime == Date.distantPast
                    if isFirstChunk || now.timeIntervalSince(lastPersistTime) >= 1.0 {
                        session.pendingStreamingContent = fullContent
                        session.updatedAt = now
                        try? modelContext.save()
                        lastPersistTime = now
                    }
                case .toolCall(let toolCall):
                    pendingToolCalls.append(toolCall)
                case .usage(let usage):
                    lastUsage = usage
                case .done:
                    break
                case .error(let error):
                    errorMessage = error
                    canRetry = true
                    return
                }
            }

            session.pendingStreamingContent = nil

            if Task.isCancelled || cancelled {
                if !fullContent.isEmpty || !pendingToolImageAttachments.isEmpty {
                    let partialMsg = Message(
                        role: .assistant,
                        content: fullContent.isEmpty ? nil : fullContent + L10n.Chat.aborted,
                        session: session
                    )
                    partialMsg.extractAndStoreInlineImages(agentId: agentId)
                    attachPendingToolImages(to: partialMsg)
                    modelContext.insert(partialMsg)
                    session.messages.append(partialMsg)
                    session.updatedAt = Date()
                    try? modelContext.save()
                    loadMessages()
                }
                canRetry = true
                return
            }

            let (cleanedContent, thinkingFromTags) = Self.extractThinkTags(from: fullContent)
            let combinedThinking: String? = {
                var parts: [String] = []
                if !fullThinking.isEmpty { parts.append(fullThinking) }
                if !thinkingFromTags.isEmpty { parts.append(thinkingFromTags) }
                return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
            }()
            let finalContent = thinkingFromTags.isEmpty ? fullContent : cleanedContent

            if !pendingToolCalls.isEmpty {
                streamingContent = ""
                streamingThinking = ""

                let assistantMsg = Message(
                    role: .assistant,
                    content: finalContent.isEmpty ? nil : finalContent,
                    toolCallsData: try? JSONEncoder().encode(pendingToolCalls),
                    session: session
                )
                assistantMsg.thinkingContent = combinedThinking
                assistantMsg.extractAndStoreInlineImages(agentId: agentId)
                Self.applyAPIUsage(lastUsage, to: assistantMsg)
                modelContext.insert(assistantMsg)
                session.messages.append(assistantMsg)
                try? modelContext.save()
                loadMessages()

                await processToolCalls(pendingToolCalls, router: router, agent: agent)
            } else if !finalContent.isEmpty || combinedThinking != nil {
                let assistantMsg = Message(role: .assistant, content: finalContent.isEmpty ? nil : finalContent, session: session)
                assistantMsg.thinkingContent = combinedThinking
                assistantMsg.extractAndStoreInlineImages(agentId: agentId)
                attachPendingToolImages(to: assistantMsg)
                Self.applyAPIUsage(lastUsage, to: assistantMsg)
                modelContext.insert(assistantMsg)
                session.messages.append(assistantMsg)
                session.updatedAt = Date()
                try? modelContext.save()
                loadMessages()
            } else if !pendingToolImageAttachments.isEmpty {
                let assistantMsg = Message(role: .assistant, content: nil, session: session)
                attachPendingToolImages(to: assistantMsg)
                Self.applyAPIUsage(lastUsage, to: assistantMsg)
                modelContext.insert(assistantMsg)
                session.messages.append(assistantMsg)
                session.updatedAt = Date()
                try? modelContext.save()
                loadMessages()
            }
        } catch {
            if Task.isCancelled || cancelled {
                if !(error is CancellationError) {
                    errorMessage = error.localizedDescription
                }
            } else {
                errorMessage = error.localizedDescription
            }
            canRetry = true
            pendingToolImageAttachments = []
        }
    }

    @MainActor
    private func processToolCalls(
        _ toolCalls: [LLMToolCall],
        router: ModelRouter,
        agent: Agent
    ) async {
        let fnRouter = FunctionCallRouter(agent: agent, modelContext: modelContext, sessionId: session.id)

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

        // Safety rule:
        // - Only `message_sub_agent` is allowed to run in parallel.
        // - All other tools (including `create_sub_agent`) stay sequential to avoid
        //   concurrent SwiftData writes and ordering issues.
        var results: [(Int, LLMToolCall, ToolCallResult)] = []
        var index = 0
        while index < toolCalls.count {
            let current = toolCalls[index]
            if current.function.name == "message_sub_agent" {
                var parallelBatch: [(Int, LLMToolCall)] = []
                var cursor = index
                while cursor < toolCalls.count, toolCalls[cursor].function.name == "message_sub_agent" {
                    parallelBatch.append((cursor, toolCalls[cursor]))
                    cursor += 1
                }

                if parallelBatch.count == 1, let only = parallelBatch.first {
                    silentStatus = "tool:\(only.1.function.name)"
                    let result = await fnRouter.execute(toolCall: only.1)
                    results.append((only.0, only.1, result))
                } else {
                    silentStatus = "tool:message_sub_agent"
                    await withTaskGroup(of: (Int, LLMToolCall, ToolCallResult).self) { group in
                        for (batchIndex, toolCall) in parallelBatch {
                            group.addTask { @MainActor in
                                let result = await fnRouter.execute(toolCall: toolCall)
                                return (batchIndex, toolCall, result)
                            }
                        }
                        for await item in group {
                            results.append(item)
                        }
                    }
                }

                index = cursor
            } else {
                silentStatus = "tool:\(current.function.name)"
                let result = await fnRouter.execute(toolCall: current)
                results.append((index, current, result))
                index += 1
            }

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
        }

        results.sort { $0.0 < $1.0 }

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

        for (_, toolCall, result) in results {
            let toolMsg = Message(
                role: .tool,
                content: result.text,
                toolCallId: toolCall.id,
                name: toolCall.function.name,
                session: session
            )
            if let images = result.imageAttachments, !images.isEmpty {
                if let data = try? JSONEncoder().encode(images) {
                    toolMsg.imageAttachmentsData = data
                    toolMsg.recalculateTokenEstimate()
                }
                pendingToolImageAttachments.append(contentsOf: images)
            }
            modelContext.insert(toolMsg)
            session.messages.append(toolMsg)
        }

        if let lastCall = results.last {
            Self.silentLastTools[session.id] = lastCall.1.function.name
        }
        silentStatus = "think:\(silentRound)"
        try? modelContext.save()
        loadMessages()

        if Task.isCancelled || cancelled {
            pendingToolImageAttachments = []
            return
        }

        await generateResponse()
    }

    /// Merge any images accumulated from tool calls into the given assistant message.
    private func attachPendingToolImages(to message: Message) {
        guard !pendingToolImageAttachments.isEmpty else { return }

        let existing: [ImageAttachment] = message.imageAttachmentsData.flatMap {
            try? JSONDecoder().decode([ImageAttachment].self, from: $0)
        } ?? []
        let all = existing + pendingToolImageAttachments
        message.imageAttachmentsData = try? JSONEncoder().encode(all)
        message.recalculateTokenEstimate()
        pendingToolImageAttachments = []
    }

    /// Compress context if active tokens exceed the threshold.
    /// Called BEFORE each LLM call so the context window stays right-sized.
    @MainActor
    private func compressIfNeeded(agent: Agent, router: ModelRouter) async {
        guard !Task.isCancelled, !cancelled else { return }
        let threshold = agent.effectiveCompressionThreshold
        let compressor = SessionCompressor(compressionThreshold: threshold)
        let contextManager = ContextManager()
        let activeTokens = contextManager.activeContextTokens(session: session)

        guard compressor.shouldCompress(session: session) else {
            print("[AutoCompress] Not needed — activeTokens=\(activeTokens), threshold=\(threshold)")
            return
        }

        print("[AutoCompress] Triggered — activeTokens=\(activeTokens) > threshold=\(threshold)")

        isCompressing = true
        session.isCompressingContext = true
        try? modelContext.save()
        defer {
            isCompressing = false
            session.isCompressingContext = false
            try? modelContext.save()
        }

        guard let provider = router.primaryProvider(for: agent) else {
            print("[AutoCompress] FAIL: No provider available for compression")
            return
        }

        let llmService = LLMService(provider: provider)
        let result = await compressor.compress(session: session, llmService: llmService)

        guard !Task.isCancelled, !cancelled else {
            print("[AutoCompress] Cancelled after compress() returned")
            return
        }

        if let result {
            compressor.commit(result: result, to: session, modelContext: modelContext)
            compressor.autoGenerateTitleIfNeeded(session: session, llmService: llmService, modelContext: modelContext)
            // Update vector embedding after compression
            SessionVectorStore(modelContext: modelContext)
                .updateEmbedding(for: session)
            let newTokens = contextManager.activeContextTokens(session: session)
            print("[AutoCompress] Committed — tokens \(activeTokens) → \(newTokens)")
        } else {
            print("[AutoCompress] compress() returned nil — compression was not applied, continuing with uncompressed context (\(activeTokens) tokens)")
        }
        loadMessages()
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
            guard let self else {
                session.isCompressingContext = false
                try? modelContext.save()
                return
            }

            defer {
                self.isCompressing = false
                self.isCancellingCompression = false
                session.isCompressingContext = false
                self.compressionTask = nil
                try? modelContext.save()
            }

            let router = ModelRouter(modelContext: modelContext)
            guard let provider = router.primaryProvider(for: agent) else {
                self.errorMessage = L10n.Chat.noCompressModel
                return
            }

            let threshold = agent.effectiveCompressionThreshold
            let compressor = SessionCompressor(compressionThreshold: threshold)
            let contextManager = ContextManager()
            let beforeTokens = contextManager.activeContextTokens(session: session)
            print("[ManualCompress] Start — activeTokens=\(beforeTokens), threshold=\(threshold)")

            let llmService = LLMService(provider: provider)
            let result = await compressor.compress(session: session, llmService: llmService)

            guard !Task.isCancelled else {
                print("[ManualCompress] Cancelled")
                return
            }

            if let result {
                compressor.commit(result: result, to: session, modelContext: modelContext)
                compressor.autoGenerateTitleIfNeeded(session: session, llmService: llmService, modelContext: modelContext)
                // Update vector embedding after manual compression
                SessionVectorStore(modelContext: modelContext)
                    .updateEmbedding(for: session)
                let afterTokens = contextManager.activeContextTokens(session: session)
                print("[ManualCompress] Committed — tokens \(beforeTokens) → \(afterTokens)")
            } else {
                print("[ManualCompress] compress() returned nil — no changes applied")
            }
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
        recoverRetryState()
        startMonitoringIfNeeded()
        checkToolUseCapability()
    }

    private func recoverRetryState() {
        guard !isLoading, !canRetry, generationTask == nil else { return }
        guard !session.isActive else { return }
        guard !Self.dismissedSessions.contains(session.id) else { return }
        guard let last = session.sortedMessages.last else { return }

        if last.role == .user {
            canRetry = true
            if errorMessage == nil, let cached = Self.cachedErrors[session.id] {
                errorMessage = cached
            }
        } else if last.role == .assistant,
                  let content = last.content,
                  content.contains(L10n.Chat.aborted) || content.contains(L10n.Chat.forceStoppedContent) {
            canRetry = true
        }
    }

    private func recoverActiveModelName() {
        guard activeModelName == nil, let agent = session.agent else { return }
        let router = ModelRouter(modelContext: modelContext)
        let chain = router.resolveProviderChainWithModels(for: agent)
        guard let primary = chain.first else { return }
        let effectiveModel = primary.modelName ?? primary.provider.modelName
        activeModelName = "\(primary.provider.name) (\(effectiveModel))"
    }

    func onViewDisappear() {
        stopMonitoring()
        compressionMonitorTask?.cancel()
        compressionMonitorTask = nil
        isCompressing = false
        cancelWatchdog?.cancel()
        cancelWatchdog = nil
        // Flush draft text to disk so it survives app quit.
        try? modelContext.save()
    }

    /// Prepare for app suspension/termination. Cancels active streams so the
    /// main thread is free to handle the system's exit signal promptly.
    func prepareForBackground() {
        streamCancelAction?()
        Self.activeStreamCancels[session.id]?()
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
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                if !session.isCompressingContext {
                    self?.loadMessages()
                    break
                }
                if !session.isActive && ticks > 5 {
                    session.isCompressingContext = false
                    try? modelContext.save()
                    self?.loadMessages()
                    break
                }
                ticks += 1
                if ticks > 120 {
                    session.isCompressingContext = false
                    try? modelContext.save()
                    break
                }
            }
            self?.isCompressing = false
            self?.compressionMonitorTask = nil
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
                self?.canRetry = false
                if let self, !self.session.isCompressingContext {
                    self.isCompressing = false
                }
                self?.loadMessages()
                self?.checkActiveSessionLock()
                self?.recoverRetryState()
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
        // Defer save so the SwiftData observation cascade doesn't block
        // the current SwiftUI update cycle (prevents main-thread hang
        // when ForEach children are invalidated synchronously).
        Task { @MainActor [modelContext] in
            try? modelContext.save()
        }
    }

    // MARK: - Image Management

    func addImage(_ uiImage: UIImage) {
        // Keep draft images inline-only (no file written to agent folder)
        // so they don't appear in the file browser before the message is sent.
        // They will be promoted to file-backed attachments in sendMessage().
        guard let attachment = ImageAttachment.from(image: uiImage) else { return }
        pendingImages.append(attachment)
        persistDraftImages()
    }

    func removeImage(id: UUID) {
        pendingImages.removeAll { $0.id == id }
        persistDraftImages()
    }

    private func persistDraftImages() {
        Self.cachedPendingImages[session.id] = pendingImages
        session.draftImagesData = pendingImages.isEmpty ? nil : try? JSONEncoder().encode(pendingImages)
    }

    // MARK: - Think Tag Extraction

    /// Extracts `<think>...</think>` blocks from content, returning cleaned content and extracted thinking.
    static func extractThinkTags(from content: String) -> (cleanedContent: String, thinking: String) {
        let pattern = "<think>(.*?)</think>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return (content, "")
        }
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)
        guard !matches.isEmpty else { return (content, "") }

        var thinkingParts: [String] = []
        for match in matches {
            if let thinkRange = Range(match.range(at: 1), in: content) {
                let extracted = String(content[thinkRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !extracted.isEmpty {
                    thinkingParts.append(extracted)
                }
            }
        }

        let cleaned = regex.stringByReplacingMatches(in: content, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, thinkingParts.joined(separator: "\n\n"))
    }

    // MARK: - API Usage

    /// Store vendor-reported token counts on the message and update the token
    /// estimate to the API-reported completion tokens when available.
    private static func applyAPIUsage(_ usage: LLMUsage?, to message: Message) {
        guard let usage else { return }
        message.apiPromptTokens = usage.promptTokens
        message.apiCompletionTokens = usage.completionTokens
        if let completionTokens = usage.completionTokens, completionTokens > 0 {
            message.tokenEstimate = completionTokens
        }
    }

    // MARK: - Info

    private(set) var compressionStats = CompressionStats(
        activeTokens: 0, threshold: 0, totalMessages: 0,
        compressedCount: 0, pendingCount: 0
    )

    func refreshCompressionStats() {
        let contextManager = ContextManager()
        let active = contextManager.activeContextTokens(session: session)
        let threshold = session.agent?.effectiveCompressionThreshold ?? ContextManager.compressionThreshold
        let compressedIdx = session.compressedUpToIndex
        let totalMsgs = session.messages.count

        let pendingEnd = max(totalMsgs - 3, compressedIdx)
        let pendingCount = max(pendingEnd - compressedIdx, 0)

        compressionStats = CompressionStats(
            activeTokens: active,
            threshold: threshold,
            totalMessages: totalMsgs,
            compressedCount: compressedIdx,
            pendingCount: pendingCount
        )
    }

    // MARK: - Related Sessions (RAG)

    /// Resolve related sessions: use persisted IDs if available, otherwise compute and persist.
    /// Called once per session start so the system prompt stays stable across turns.
    static func resolveRelatedSessions(
        session: Session,
        modelContext: ModelContext
    ) -> [(id: UUID, title: String, updatedAt: Date)] {
        // If already computed, look up the persisted session objects
        let existingIds = session.relatedSessionIds
        if !existingIds.isEmpty {
            return lookupSessions(ids: existingIds, modelContext: modelContext)
        }

        // First generation — compute via hybrid search (local vector + keyword) and persist
        let sessionService = SessionService(modelContext: modelContext)
        let found = sessionService.findRelatedSessionsHybrid(for: session, maxResults: 5)
        if !found.isEmpty {
            session.relatedSessionIds = found.map(\.id)
            try? modelContext.save()
        }
        return found
    }

    private static func lookupSessions(
        ids: [UUID],
        modelContext: ModelContext
    ) -> [(id: UUID, title: String, updatedAt: Date)] {
        var results: [(id: UUID, title: String, updatedAt: Date)] = []
        for sessionId in ids {
            var descriptor = FetchDescriptor<Session>()
            descriptor.predicate = #Predicate { $0.id == sessionId }
            descriptor.fetchLimit = 1
            if let session = (try? modelContext.fetch(descriptor))?.first {
                results.append((id: session.id, title: session.title, updatedAt: session.updatedAt))
            }
        }
        return results
    }

    // MARK: - Modality Stripping

    /// Removes image content parts from context messages when the target model
    /// lacks vision support. Returns the number of images that were stripped.
    @discardableResult
    static func stripUnsupportedModalities(
        from messages: inout [LLMChatMessage],
        capabilities: ModelCapabilities
    ) -> Int {
        guard !capabilities.supportsVision else { return 0 }

        var strippedCount = 0
        var indicesToRemove: [Int] = []
        for i in messages.indices {
            guard let parts = messages[i].contentParts else { continue }
            let imageCount = parts.filter { if case .imageURL = $0 { return true }; return false }.count
            guard imageCount > 0 else { continue }
            strippedCount += imageCount

            // Clear contentParts entirely so the encoder falls back to
            // plain string `content`, which all APIs accept for any role.
            let hasTextContent = !(messages[i].content ?? "").isEmpty
            let hasToolCalls = messages[i].toolCalls != nil
            if !hasTextContent && !hasToolCalls && messages[i].toolCallId == nil {
                // Synthetic image-only message (e.g. flush from ContextManager) — remove entirely
                indicesToRemove.append(i)
            } else {
                messages[i] = LLMChatMessage(
                    role: messages[i].role,
                    content: messages[i].content,
                    contentParts: nil,
                    toolCalls: messages[i].toolCalls,
                    toolCallId: messages[i].toolCallId,
                    name: messages[i].name
                )
            }
        }
        for i in indicesToRemove.reversed() {
            messages.remove(at: i)
        }
        return strippedCount
    }
}

struct CompressionStats {
    let activeTokens: Int
    let threshold: Int
    let totalMessages: Int
    let compressedCount: Int
    /// Messages eligible for the next compression pass.
    let pendingCount: Int

    var activeFormatted: String { Self.fmt(activeTokens) }
    var thresholdFormatted: String { Self.fmt(threshold) }

    var tokenRatio: Double {
        guard threshold > 0 else { return 0 }
        return Double(activeTokens) / Double(threshold)
    }

    private static func fmt(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000.0) : "\(n)"
    }
}

enum ChatError: LocalizedError {
    case noProviderConfigured
    case noAgentAssociated
    case whitelistBlockedAllModels

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured:
            return L10n.ChatError.noProvider
        case .noAgentAssociated:
            return L10n.ChatError.noAgent
        case .whitelistBlockedAllModels:
            return L10n.ChatError.whitelistBlocked
        }
    }
}
