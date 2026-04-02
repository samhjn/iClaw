import Foundation
import SwiftData
import Observation

struct SessionRowData {
    let messageCount: Int
    let previewContent: String?
    let isStreaming: Bool
    let hasDraft: Bool
}

@Observable
final class SessionListViewModel {
    var sessions: [Session] = []
    var rowDataCache: [UUID: SessionRowData] = [:]
    var selectedSession: Session?
    var sessionToDelete: Session?
    var searchText: String = ""

    private var allSessions: [Session] = []
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
        allSessions = all.filter { !$0.isArchived && $0.agent?.parentAgent == nil }
        applySearch()
    }

    func applySearch() {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sessions = allSessions
        } else {
            let keywords = SessionService.extractSearchKeywords(from: searchText)
            if keywords.isEmpty {
                sessions = allSessions
            } else {
                sessions = allSessions.filter { session in
                    let titleLower = session.title.lowercased()
                    for keyword in keywords {
                        if titleLower.contains(keyword) { return true }
                    }
                    // Check last message preview
                    if let lastMsg = session.messages.max(by: { $0.timestamp < $1.timestamp }),
                       let content = lastMsg.content?.lowercased() {
                        for keyword in keywords {
                            if content.contains(keyword) { return true }
                        }
                    }
                    // Check agent name
                    if let agentName = session.agent?.name.lowercased() {
                        for keyword in keywords {
                            if agentName.contains(keyword) { return true }
                        }
                    }
                    return false
                }
            }
        }
        rebuildRowDataCache()
    }

    private func rebuildRowDataCache() {
        var cache: [UUID: SessionRowData] = [:]
        cache.reserveCapacity(sessions.count)
        for session in sessions {
            let isStreaming = session.isActive && session.pendingStreamingContent != nil
                && !session.pendingStreamingContent!.isEmpty
            let rawPreview: String? = {
                if isStreaming {
                    return session.pendingStreamingContent
                }
                if let lastMessage = session.messages.max(by: { $0.timestamp < $1.timestamp }),
                   let content = lastMessage.content {
                    return content
                }
                return nil
            }()
            let preview = rawPreview.map { Self.sanitizePreview($0) }
            let hasDraft: Bool = {
                if let draft = session.draftText, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return true
                }
                if session.draftImagesData != nil {
                    return true
                }
                return ChatViewModel.hasCachedInput(for: session.id)
            }()
            cache[session.id] = SessionRowData(
                messageCount: session.messages.count,
                previewContent: preview,
                isStreaming: isStreaming,
                hasDraft: hasDraft
            )
        }
        rowDataCache = cache
    }

    private static let imagePattern = try! NSRegularExpression(
        pattern: "!\\[[^\\]]*\\]\\([^)]+\\)",
        options: []
    )

    private static func sanitizePreview(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        let cleaned = imagePattern.stringByReplacingMatches(
            in: text, options: [], range: range, withTemplate: "[图片]"
        )
        let maxLength = 200
        if cleaned.count > maxLength {
            return String(cleaned.prefix(maxLength))
        }
        return cleaned
    }

    func startAutoRefresh() {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, !Task.isCancelled else { return }
                let hasActive = self.sessions.contains { $0.isActive }
                try? await Task.sleep(for: .seconds(hasActive ? 2 : 4))
                guard !Task.isCancelled else { return }
                self.fetchSessions()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    func createSession(agent: Agent) -> Session {
        let session = Session(title: L10n.Chat.newChat)
        modelContext.insert(session)
        session.agent = agent
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
