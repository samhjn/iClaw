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

    init(title: String, agent: Agent? = nil) {
        self.id = UUID()
        self.agent = agent
        self.title = title
        self.messages = []
        self.compressedContext = nil
        self.compressedUpToIndex = 0
        self.isArchived = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var sortedMessages: [Message] {
        messages.sorted { $0.timestamp < $1.timestamp }
    }
}
