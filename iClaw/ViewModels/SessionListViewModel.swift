import Foundation
import SwiftData
import Observation

@Observable
final class SessionListViewModel {
    var sessions: [Session] = []
    var selectedSession: Session?

    private var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchSessions()
    }

    func fetchSessions() {
        let descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        sessions = all.filter { !$0.isArchived && $0.agent?.parentAgent == nil }
    }

    func createSession(agent: Agent) -> Session {
        let session = Session(title: L10n.Chat.newChat, agent: agent)
        modelContext.insert(session)
        try? modelContext.save()
        fetchSessions()
        return session
    }

    func deleteSession(_ session: Session) {
        modelContext.delete(session)
        try? modelContext.save()
        fetchSessions()
    }

    func deleteSessionAtOffsets(_ offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            modelContext.delete(session)
        }
        try? modelContext.save()
        fetchSessions()
    }
}
