import Foundation
import SwiftData

/// Manages sub-agent lifecycle: creation, messaging, inflight tracking, stop, and cleanup.
final class SubAgentManager {
    private let agentService: AgentService
    private let modelContext: ModelContext

    /// Maps subAgentId → active session for that agent.
    private var activeSessions: [UUID: Session] = [:]

    /// Tracks in-flight tasks by subAgentId so they can be cancelled.
    private var inflightTasks: [UUID: Task<String, Error>] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.agentService = AgentService(modelContext: modelContext)
    }

    // MARK: - Create

    func createSubAgent(
        name: String,
        parentAgent: Agent,
        initialContext: String?,
        providerIdOverride: UUID? = nil,
        type: SubAgentType = .temp,
        parentSessionId: UUID? = nil
    ) -> (agent: Agent, session: Session) {
        let subAgent = agentService.createSubAgent(
            name: name,
            parentAgent: parentAgent,
            initialContext: initialContext
        )
        subAgent.subAgentType = type.rawValue

        if let overrideId = providerIdOverride {
            subAgent.primaryProviderId = overrideId
        } else if let subDefault = parentAgent.subAgentProviderId {
            subAgent.primaryProviderId = subDefault
            subAgent.primaryModelNameOverride = parentAgent.subAgentModelNameOverride
        } else {
            // Resolve the parent's actual primary provider (including global default fallback)
            // so the sub-agent inherits the effective model, not just the raw field.
            let router = ModelRouter(modelContext: modelContext)
            let resolvedChain = router.resolveProviderChainWithModels(for: parentAgent)
            if let primary = resolvedChain.first {
                subAgent.primaryProviderId = primary.provider.id
                subAgent.primaryModelNameOverride = primary.modelName
            } else {
                subAgent.primaryProviderId = parentAgent.primaryProviderId
                subAgent.primaryModelNameOverride = parentAgent.primaryModelNameOverride
            }
        }
        // Copy fallback chain: resolve parent's effective chain, skip the first (primary).
        let router = ModelRouter(modelContext: modelContext)
        let fullChain = router.resolveProviderChainWithModels(for: parentAgent)
        if fullChain.count > 1 {
            let fallbacks = Array(fullChain.dropFirst())
            subAgent.fallbackProviderIds = fallbacks.map { $0.provider.id }
            subAgent.fallbackModelNames = fallbacks.map { $0.modelName ?? "" }
        } else {
            subAgent.fallbackProviderIds = parentAgent.fallbackProviderIds
            subAgent.fallbackModelNamesRaw = parentAgent.fallbackModelNamesRaw
        }

        try? modelContext.save()

        let session = Session(title: "Sub: \(name)", agent: subAgent)
        session.parentSessionIdRaw = parentSessionId?.uuidString
        modelContext.insert(session)
        try? modelContext.save()

        activeSessions[subAgent.id] = session

        return (subAgent, session)
    }

    // MARK: - Message (with tool call loop)

    @MainActor
    func sendMessage(
        to subAgentId: UUID,
        content: String
    ) async throws -> String {
        guard let subAgent = agentService.fetchAgent(id: subAgentId),
              let session = activeSessions[subAgentId] ?? subAgent.sessions.last else {
            throw SubAgentError.agentNotFound
        }

        let userMsg = Message(role: .user, content: content, session: session)
        modelContext.insert(userMsg)
        session.messages.append(userMsg)
        session.isActive = true
        try? modelContext.save()

        defer {
            session.isActive = false
            try? modelContext.save()
        }

        let response = try await runAgentLoop(subAgent: subAgent, session: session)

        // If temp agent, mark session content and clean up
        if subAgent.isTempSubAgent {
            scheduleCleanup(subAgent: subAgent)
        }

        return response
    }

    /// Full agent loop: send, process tool calls, repeat until text response.
    @MainActor
    private func runAgentLoop(
        subAgent: Agent,
        session: Session,
        maxRounds: Int = 10
    ) async throws -> String {
        let router = ModelRouter(modelContext: modelContext)
        let promptBuilder = PromptBuilder()
        let contextManager = ContextManager()
        let fnRouter = FunctionCallRouter(agent: subAgent, modelContext: modelContext, sessionId: session.id)

        for _ in 0..<maxRounds {
            let systemPrompt = promptBuilder.buildSystemPrompt(for: subAgent, isSubAgent: true)
            let messages = contextManager.buildContextWindow(session: session, systemPrompt: systemPrompt)

            let (response, _) = try await router.chatCompletionWithFailover(
                agent: subAgent,
                messages: messages,
                tools: ToolDefinitions.allTools
            )

            guard let choice = response.choices.first, let msg = choice.message else {
                throw SubAgentError.emptyResponse
            }

            if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                let assistantMsg = Message(
                    role: .assistant,
                    content: msg.content,
                    toolCallsData: try? JSONEncoder().encode(toolCalls),
                    session: session
                )
                modelContext.insert(assistantMsg)
                session.messages.append(assistantMsg)

                for tc in toolCalls {
                    let result = await fnRouter.execute(toolCall: tc)
                    let toolMsg = Message(
                        role: .tool,
                        content: result,
                        toolCallId: tc.id,
                        name: tc.function.name,
                        session: session
                    )
                    modelContext.insert(toolMsg)
                    session.messages.append(toolMsg)
                }
                try? modelContext.save()
                continue
            }

            if let content = msg.content, !content.isEmpty {
                let assistantMsg = Message(role: .assistant, content: content, session: session)
                modelContext.insert(assistantMsg)
                session.messages.append(assistantMsg)
                session.updatedAt = Date()
                try? modelContext.save()
                return content
            }

            break
        }

        throw SubAgentError.emptyResponse
    }

    // MARK: - Inflight Management

    /// Returns all inflight (active) sub-agent sessions for a parent agent.
    func inflightSubAgentSessions(for parentAgent: Agent) -> [(agent: Agent, session: Session)] {
        parentAgent.subAgents.compactMap { sub in
            guard let session = activeSessions[sub.id] ?? sub.sessions.last,
                  session.isActive else { return nil }
            return (sub, session)
        }
    }

    /// Returns all sub-agent sessions (active or not) for a parent agent.
    func allSubAgentSessions(for parentAgent: Agent) -> [(agent: Agent, session: Session, isActive: Bool)] {
        parentAgent.subAgents.compactMap { sub in
            guard let session = activeSessions[sub.id] ?? sub.sessions.last else { return nil }
            return (sub, session, session.isActive)
        }
    }

    /// Force-stop an inflight sub-agent session.
    func forceStop(subAgentId: UUID) {
        inflightTasks[subAgentId]?.cancel()
        inflightTasks[subAgentId] = nil

        if let session = activeSessions[subAgentId] {
            session.isActive = false
            try? modelContext.save()
        }
    }

    // MARK: - Content Relay

    /// Generates a summary of the sub-agent session's output for the parent session.
    func collectSessionSummary(subAgentId: UUID) -> String {
        guard let subAgent = agentService.fetchAgent(id: subAgentId),
              let session = activeSessions[subAgentId] ?? subAgent.sessions.last else {
            return "[Error] Sub-agent session not found."
        }

        let assistantMessages = session.sortedMessages
            .filter { $0.role == .assistant }
            .compactMap { $0.content }

        if assistantMessages.isEmpty {
            return "(No output from sub-agent)"
        }

        return assistantMessages.joined(separator: "\n\n---\n\n")
    }

    /// Returns the full transcript of a sub-agent session for injection into parent context.
    func collectFullTranscript(subAgentId: UUID) -> String {
        guard let subAgent = agentService.fetchAgent(id: subAgentId),
              let session = activeSessions[subAgentId] ?? subAgent.sessions.last else {
            return "[Error] Sub-agent session not found."
        }

        return session.sortedMessages.compactMap { msg in
            let role = msg.role.rawValue.capitalized
            guard let content = msg.content, !content.isEmpty else { return nil }
            return "[\(role)] \(content)"
        }.joined(separator: "\n\n")
    }

    // MARK: - Cleanup

    /// Schedule cleanup of a temp sub-agent (delete agent + sessions).
    private func scheduleCleanup(subAgent: Agent) {
        guard subAgent.isTempSubAgent else { return }
        // Don't delete immediately — the caller may still need the response.
        // The caller should invoke `destroyTempAgent` when ready.
    }

    /// Destroy a temp sub-agent and all its data.
    func destroyTempAgent(_ subAgentId: UUID) {
        guard let subAgent = agentService.fetchAgent(id: subAgentId),
              subAgent.isTempSubAgent else { return }
        activeSessions.removeValue(forKey: subAgentId)
        inflightTasks.removeValue(forKey: subAgentId)
        modelContext.delete(subAgent)
        try? modelContext.save()
    }

    /// Delete a persistent sub-agent (by main agent or user).
    func deletePersistentAgent(_ subAgentId: UUID) {
        guard let subAgent = agentService.fetchAgent(id: subAgentId) else { return }
        forceStop(subAgentId: subAgentId)
        activeSessions.removeValue(forKey: subAgentId)
        inflightTasks.removeValue(forKey: subAgentId)
        modelContext.delete(subAgent)
        try? modelContext.save()
    }
}

enum SubAgentType: String {
    case temp
    case persistent
}

enum SubAgentError: LocalizedError {
    case agentNotFound
    case emptyResponse
    case sessionLocked(String)

    var errorDescription: String? {
        switch self {
        case .agentNotFound: return "Sub-agent not found"
        case .emptyResponse: return "Sub-agent returned an empty response"
        case .sessionLocked(let reason): return "Session locked: \(reason)"
        }
    }
}
