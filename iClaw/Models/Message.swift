import Foundation
import SwiftData

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
    case tool
}

@Model
final class Message {
    var id: UUID
    var session: Session?
    var roleRaw: String
    var content: String?
    var toolCallsData: Data?
    var toolCallId: String?
    var name: String?
    var timestamp: Date
    var tokenEstimate: Int

    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    init(
        role: MessageRole,
        content: String? = nil,
        toolCallsData: Data? = nil,
        toolCallId: String? = nil,
        name: String? = nil,
        session: Session? = nil,
        tokenEstimate: Int = 0
    ) {
        self.id = UUID()
        self.session = session
        self.roleRaw = role.rawValue
        self.content = content
        self.toolCallsData = toolCallsData
        self.toolCallId = toolCallId
        self.name = name
        self.timestamp = Date()
        self.tokenEstimate = tokenEstimate
    }
}
