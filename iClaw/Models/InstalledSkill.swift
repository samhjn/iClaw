import Foundation
import SwiftData

@Model
final class InstalledSkill {
    var id: UUID
    var agent: Agent?
    var skill: Skill?
    var isEnabled: Bool
    var installedAt: Date

    init(isEnabled: Bool = true) {
        self.id = UUID()
        self.isEnabled = isEnabled
        self.installedAt = Date()
    }
}
