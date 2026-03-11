import Foundation
import SwiftData

@Model
final class Skill {
    var id: UUID
    var name: String
    var summary: String
    var content: String
    var tagsRaw: String
    var author: String
    var version: String
    var isBuiltIn: Bool
    @Relationship(deleteRule: .cascade, inverse: \InstalledSkill.skill)
    var installations: [InstalledSkill]
    var createdAt: Date
    var updatedAt: Date

    var tags: [String] {
        get { tagsRaw.isEmpty ? [] : tagsRaw.components(separatedBy: ",") }
        set { tagsRaw = newValue.joined(separator: ",") }
    }

    var installCount: Int { installations.count }

    init(
        name: String,
        summary: String,
        content: String,
        tags: [String] = [],
        author: String = "user",
        version: String = "1.0",
        isBuiltIn: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.summary = summary
        self.content = content
        self.tagsRaw = tags.joined(separator: ",")
        self.author = author
        self.version = version
        self.isBuiltIn = isBuiltIn
        self.installations = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
