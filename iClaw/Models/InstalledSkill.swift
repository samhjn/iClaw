import Foundation
import SwiftData

@Model
final class InstalledSkill {
    var id: UUID
    var agent: Agent?
    var skill: Skill?
    var isEnabled: Bool
    var installedAt: Date

    init(agent: Agent, skill: Skill, isEnabled: Bool = true) {
        self.id = UUID()
        self.agent = agent
        self.skill = skill
        self.isEnabled = isEnabled
        self.installedAt = Date()
    }
}
