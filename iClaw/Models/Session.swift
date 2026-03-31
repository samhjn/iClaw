import Foundation
import SwiftData

@Model
final class Session {
    var id: UUID
    var agent: Agent?
    var title: String
    @Relationship(deleteRule: .cascade, inverse: \Message.session)
    var messages: [Message]
    var compressedContext: String?
    var compressedUpToIndex: Int
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    /// Whether this session is currently active (agent is generating / processing).
    var isActive: Bool = false

    /// Whether context compression is currently in progress.
    var isCompressingContext: Bool = false

    /// Whether the user has manually renamed this session's title.
    var isTitleCustomized: Bool = false

    /// UUID of the last message visible when the user left this session (for scroll restoration).
    var lastViewedMessageIdRaw: String?

    var lastViewedMessageId: UUID? {
        get { lastViewedMessageIdRaw.flatMap { UUID(uuidString: $0) } }
        set { lastViewedMessageIdRaw = newValue?.uuidString }
    }

    /// Partial streaming content from assistant (persisted so re-entry can display progress).
    var pendingStreamingContent: String?

    /// Draft text the user was typing but hasn't sent yet (persisted across app quit / session exit).
    var draftText: String?

    /// UUID of the parent session that spawned this sub-agent session (for content relay).
    var parentSessionIdRaw: String?

    var parentSessionId: UUID? {
        get { parentSessionIdRaw.flatMap { UUID(uuidString: $0) } }
        set { parentSessionIdRaw = newValue?.uuidString }
    }

    init(title: String, agent: Agent? = nil) {
        self.id = UUID()
        self.agent = agent
        self.title = title
        self.messages = []
        self.compressedContext = nil
        self.compressedUpToIndex = 0
        self.isArchived = false
        self.isActive = false
        self.isTitleCustomized = false
        self.lastViewedMessageIdRaw = nil
        self.parentSessionIdRaw = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var sortedMessages: [Message] {
        messages.sorted { $0.timestamp < $1.timestamp }
    }
}
