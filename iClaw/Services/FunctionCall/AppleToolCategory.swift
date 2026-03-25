import Foundation

/// Permission level for an Apple tool category on a specific agent.
enum AppleToolPermissionLevel: String, Codable, CaseIterable {
    case readWrite = "rw"
    case readOnly = "r"
    case writeOnly = "w"
    case disabled = "-"

    var allowsRead: Bool { self == .readWrite || self == .readOnly }
    var allowsWrite: Bool { self == .readWrite || self == .writeOnly }

    var displayLabel: String {
        switch self {
        case .readWrite: return L10n.ApplePermissions.readWrite
        case .readOnly:  return L10n.ApplePermissions.readOnly
        case .writeOnly: return L10n.ApplePermissions.writeOnly
        case .disabled:  return L10n.ApplePermissions.disabled
        }
    }

    var iconName: String {
        switch self {
        case .readWrite: return "checkmark.circle.fill"
        case .readOnly:  return "eye.fill"
        case .writeOnly: return "pencil.circle.fill"
        case .disabled:  return "xmark.circle"
        }
    }

    var iconColor: String {
        switch self {
        case .readWrite: return "green"
        case .readOnly:  return "blue"
        case .writeOnly: return "orange"
        case .disabled:  return "gray"
        }
    }
}

/// Defines an Apple ecosystem tool category with its associated read & write tool names.
enum AppleToolCategory: String, CaseIterable, Identifiable {
    case calendar
    case reminders
    case contacts
    case clipboard
    case notifications
    case location
    case map
    case health

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calendar:      return L10n.ApplePermissions.calendar
        case .reminders:     return L10n.ApplePermissions.reminders
        case .contacts:      return L10n.ApplePermissions.contacts
        case .clipboard:     return L10n.ApplePermissions.clipboard
        case .notifications: return L10n.ApplePermissions.notifications
        case .location:      return L10n.ApplePermissions.location
        case .map:           return L10n.ApplePermissions.map
        case .health:        return L10n.ApplePermissions.health
        }
    }

    var systemImage: String {
        switch self {
        case .calendar:      return "calendar"
        case .reminders:     return "checklist"
        case .contacts:      return "person.crop.circle"
        case .clipboard:     return "doc.on.clipboard"
        case .notifications: return "bell"
        case .location:      return "location"
        case .map:           return "map"
        case .health:        return "heart.text.square"
        }
    }

    var hasWriteTools: Bool { !writeToolNames.isEmpty }

    var readToolNames: [String] {
        switch self {
        case .calendar:
            return ["calendar_list_calendars", "calendar_search_events"]
        case .reminders:
            return ["reminder_list", "reminder_lists"]
        case .contacts:
            return ["contacts_search", "contacts_get_detail"]
        case .clipboard:
            return ["clipboard_read"]
        case .notifications:
            return ["notification_list"]
        case .location:
            return ["location_get_current", "location_geocode", "location_reverse_geocode"]
        case .map:
            return ["map_search_places", "map_get_directions"]
        case .health:
            return [
                "health_read_steps", "health_read_heart_rate", "health_read_sleep",
                "health_read_body_mass", "health_read_blood_pressure", "health_read_blood_glucose",
                "health_read_blood_oxygen", "health_read_body_temperature",
            ]
        }
    }

    var writeToolNames: [String] {
        switch self {
        case .calendar:
            return ["calendar_create_event", "calendar_update_event", "calendar_delete_event"]
        case .reminders:
            return ["reminder_create", "reminder_complete", "reminder_delete"]
        case .contacts:
            return []
        case .clipboard:
            return ["clipboard_write"]
        case .notifications:
            return ["notification_schedule", "notification_cancel"]
        case .location:
            return []
        case .map:
            return []
        case .health:
            return [
                "health_write_dietary_energy", "health_write_body_mass", "health_write_dietary_water",
                "health_write_dietary_carbohydrates", "health_write_dietary_protein",
                "health_write_dietary_fat", "health_write_blood_pressure", "health_write_body_fat",
                "health_write_height", "health_write_blood_glucose", "health_write_blood_oxygen",
                "health_write_body_temperature", "health_write_heart_rate", "health_write_workout",
            ]
        }
    }

    var allToolNames: [String] { readToolNames + writeToolNames }

    /// Available permission levels for this category.
    var availableLevels: [AppleToolPermissionLevel] {
        if writeToolNames.isEmpty {
            return [.readWrite, .disabled]
        }
        return AppleToolPermissionLevel.allCases
    }

    // MARK: - Bridge action names (used by JS apple.* API)

    var bridgeReadActions: [String] {
        switch self {
        case .calendar:      return ["calendar.listCalendars", "calendar.searchEvents"]
        case .reminders:     return ["reminders.list", "reminders.lists"]
        case .contacts:      return ["contacts.search", "contacts.getDetail"]
        case .clipboard:     return ["clipboard.read"]
        case .notifications: return ["notifications.list"]
        case .location:      return ["location.getCurrent", "location.geocode", "location.reverseGeocode"]
        case .map:           return ["maps.searchPlaces", "maps.getDirections"]
        case .health:
            return [
                "health.readSteps", "health.readHeartRate", "health.readSleep",
                "health.readBodyMass", "health.readBloodPressure", "health.readBloodGlucose",
                "health.readBloodOxygen", "health.readBodyTemperature",
            ]
        }
    }

    var bridgeWriteActions: [String] {
        switch self {
        case .calendar:      return ["calendar.createEvent", "calendar.updateEvent", "calendar.deleteEvent"]
        case .reminders:     return ["reminders.create", "reminders.complete", "reminders.delete"]
        case .contacts:      return []
        case .clipboard:     return ["clipboard.write"]
        case .notifications: return ["notifications.schedule", "notifications.cancel"]
        case .location:      return []
        case .map:           return []
        case .health:
            return [
                "health.writeDietaryEnergy", "health.writeBodyMass", "health.writeDietaryWater",
                "health.writeDietaryCarbohydrates", "health.writeDietaryProtein",
                "health.writeDietaryFat", "health.writeBloodPressure", "health.writeBodyFat",
                "health.writeHeight", "health.writeBloodGlucose", "health.writeBloodOxygen",
                "health.writeBodyTemperature", "health.writeHeartRate", "health.writeWorkout",
            ]
        }
    }

    var allBridgeActions: [String] { bridgeReadActions + bridgeWriteActions }

    // MARK: - Static helpers

    /// All Apple tool names across every category.
    static let allAppleToolNames: Set<String> = {
        var names = Set<String>()
        for cat in AppleToolCategory.allCases {
            names.formUnion(cat.allToolNames)
        }
        return names
    }()

    /// Look up the category for a given tool name.
    static func category(for toolName: String) -> AppleToolCategory? {
        for cat in AppleToolCategory.allCases {
            if cat.allToolNames.contains(toolName) { return cat }
        }
        return nil
    }

    /// Whether the tool name is a write operation in its category.
    static func isWriteTool(_ toolName: String) -> Bool {
        for cat in AppleToolCategory.allCases {
            if cat.writeToolNames.contains(toolName) { return true }
        }
        return false
    }

    /// All bridge action names across every category.
    static let allBridgeActionNames: Set<String> = {
        var names = Set<String>()
        for cat in AppleToolCategory.allCases {
            names.formUnion(cat.allBridgeActions)
        }
        return names
    }()

    /// Look up the category for a bridge action name (e.g. "calendar.searchEvents").
    static func category(forBridgeAction action: String) -> AppleToolCategory? {
        for cat in AppleToolCategory.allCases {
            if cat.allBridgeActions.contains(action) { return cat }
        }
        return nil
    }

    /// Whether the bridge action is a write operation.
    static func isBridgeWriteAction(_ action: String) -> Bool {
        for cat in AppleToolCategory.allCases {
            if cat.bridgeWriteActions.contains(action) { return true }
        }
        return false
    }

    /// Compute the set of blocked bridge actions for a given agent.
    static func blockedBridgeActions(for agent: Agent) -> Set<String> {
        var blocked = Set<String>()
        for cat in AppleToolCategory.allCases {
            let level = agent.permissionLevel(for: cat)
            if !level.allowsRead {
                blocked.formUnion(cat.bridgeReadActions)
            }
            if !level.allowsWrite {
                blocked.formUnion(cat.bridgeWriteActions)
            }
        }
        return blocked
    }
}
