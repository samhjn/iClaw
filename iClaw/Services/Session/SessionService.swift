import Foundation
import SwiftData

final class SessionService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func createSession(title: String, agent: Agent) -> Session {
        let session = Session(title: title, agent: agent)
        modelContext.insert(session)
        try? modelContext.save()
        return session
    }

    func updateTitle(_ session: Session, title: String) {
        session.title = title
        session.updatedAt = Date()
        try? modelContext.save()
    }

    func archiveSession(_ session: Session) {
        session.isArchived = true
        session.updatedAt = Date()
        try? modelContext.save()
    }

    func deleteSession(_ session: Session) {
        modelContext.delete(session)
        try? modelContext.save()
    }

    func fetchSessions(for agent: Agent, includeArchived: Bool = false) -> [Session] {
        let agentId = agent.id
        var descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if !includeArchived {
            descriptor.predicate = #Predicate {
                $0.agent?.id == agentId && $0.isArchived == false
            }
        } else {
            descriptor.predicate = #Predicate {
                $0.agent?.id == agentId
            }
        }
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func addMessage(to session: Session, role: MessageRole, content: String?, toolCallsData: Data? = nil, toolCallId: String? = nil, name: String? = nil) -> Message {
        let tokenEstimate = estimateTokens(content ?? "")
        let message = Message(
            role: role,
            content: content,
            toolCallsData: toolCallsData,
            toolCallId: toolCallId,
            name: name,
            session: session,
            tokenEstimate: tokenEstimate
        )
        modelContext.insert(message)
        session.messages.append(message)
        session.updatedAt = Date()
        try? modelContext.save()
        return message
    }

    private func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }
}
