import Foundation
import SwiftData

final class SubAgentManager {
    private let agentService: AgentService
    private let modelContext: ModelContext
    private var activeSessions: [UUID: Session] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.agentService = AgentService(modelContext: modelContext)
    }

    func createSubAgent(
        name: String,
        parentAgent: Agent,
        initialContext: String?,
        providerIdOverride: UUID? = nil
    ) -> (agent: Agent, session: Session) {
        let subAgent = agentService.createSubAgent(
            name: name,
            parentAgent: parentAgent,
            initialContext: initialContext
        )

        if let overrideId = providerIdOverride {
            subAgent.primaryProviderId = overrideId
        } else if let subDefault = parentAgent.subAgentProviderId {
            subAgent.primaryProviderId = subDefault
        } else {
            subAgent.primaryProviderId = parentAgent.primaryProviderId
        }
        subAgent.fallbackProviderIds = parentAgent.fallbackProviderIds

        try? modelContext.save()

        let session = Session(title: "Sub: \(name)", agent: subAgent)
        modelContext.insert(session)
        try? modelContext.save()

        activeSessions[subAgent.id] = session

        return (subAgent, session)
    }

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

        let router = ModelRouter(modelContext: modelContext)
        let promptBuilder = PromptBuilder()
        let contextManager = ContextManager()

        let systemPrompt = promptBuilder.buildSystemPrompt(for: subAgent, isSubAgent: true)
        let messages = contextManager.buildContextWindow(session: session, systemPrompt: systemPrompt)

        let (response, _) = try await router.chatCompletionWithFailover(
            agent: subAgent,
            messages: messages,
            tools: ToolDefinitions.allTools
        )

        guard let choice = response.choices.first,
              let assistantContent = choice.message?.content else {
            throw SubAgentError.emptyResponse
        }

        let assistantMsg = Message(role: .assistant, content: assistantContent, session: session)
        modelContext.insert(assistantMsg)
        session.messages.append(assistantMsg)
        try? modelContext.save()

        return assistantContent
    }
}

enum SubAgentError: LocalizedError {
    case agentNotFound
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .agentNotFound: return "Sub-agent not found"
        case .emptyResponse: return "Sub-agent returned an empty response"
        }
    }
}
