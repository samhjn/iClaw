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
    var thinkingContent: String?
    var imageAttachmentsData: Data?
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
        if tokenEstimate > 0 {
            self.tokenEstimate = tokenEstimate
        } else {
            self.tokenEstimate = Self.computeTokenEstimate(
                content: content,
                toolCallsData: toolCallsData,
                name: name
            )
        }
    }

    /// Compute a BPE-aware token estimate from the message payload.
    private static func computeTokenEstimate(
        content: String?,
        toolCallsData: Data?,
        name: String?
    ) -> Int {
        let overhead = 4
        var total = overhead

        if let content {
            total += TokenEstimator.estimate(content)
        }

        if let toolData = toolCallsData {
            if let calls = try? JSONDecoder().decode([LLMToolCall].self, from: toolData) {
                for call in calls {
                    total += TokenEstimator.estimate(call.function.name)
                    total += TokenEstimator.estimate(call.function.arguments)
                    total += 8
                }
            }
        }

        if let name {
            total += TokenEstimator.estimate(name) + 1
        }

        return total
    }
}
