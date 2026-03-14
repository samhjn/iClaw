import Foundation
import SwiftData
import Observation

@Observable
final class SessionListViewModel {
    var sessions: [Session] = []
    var selectedSession: Session?
    var sessionToDelete: Session?

    private var modelContext: ModelContext
    private var autoRefreshTask: Task<Void, Never>?

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

    func startAutoRefresh() {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                let hasActive = self.sessions.contains { $0.isActive }
                if hasActive {
                    self.fetchSessions()
                }
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
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
