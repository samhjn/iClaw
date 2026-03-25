import Foundation
import WebKit
import os.log

private let bridgeLog = OSLog(subsystem: "com.iclaw.jsruntime", category: "apple-bridge")

/// Bridges Apple ecosystem APIs into the WKWebView JS sandbox.
///
/// Uses WKScriptMessageHandlerWithReply so JavaScript can call native APIs
/// synchronously via `window.webkit.messageHandlers.appleBridge.postMessage()`
/// and receive results inline.
///
/// The bridge installs a high-level `apple` global object with sub-namespaces:
/// `apple.calendar.*`, `apple.reminders.*`, `apple.contacts.*`, `apple.clipboard.*`,
/// `apple.notifications.*`, `apple.location.*`, `apple.maps.*`, `apple.health.*`.
///
/// Per-agent permissions are enforced in two layers:
/// 1. **JS layer**: blocked actions are injected into the preamble and rejected before `postMessage`.
/// 2. **Native layer**: each execution registers a permission checker keyed by `execId`;
///    `dispatch` looks up the checker and rejects unauthorized calls even if JS was tampered with.
@MainActor
final class AppleEcosystemBridge: NSObject, WKScriptMessageHandlerWithReply {

    static let shared = AppleEcosystemBridge()
    private override init() { super.init() }

    static let messageHandlerName = "appleBridge"

    /// Permission checkers keyed by execution ID.
    /// Each JS execution registers a checker before running and removes it after.
    private var permissionCheckers: [String: (String) -> Bool] = [:]

    /// Install the bridge on a WKWebView configuration before the web view is created.
    func install(on configuration: WKWebViewConfiguration) {
        configuration.userContentController.addScriptMessageHandler(
            self, contentWorld: .page, name: Self.messageHandlerName)
    }

    /// Remove the bridge when tearing down.
    func uninstall(from configuration: WKWebViewConfiguration) {
        configuration.userContentController.removeScriptMessageHandler(
            forName: Self.messageHandlerName, contentWorld: .page)
    }

    // MARK: - Permission Registration

    /// Register a permission checker for a JS execution context.
    func registerPermissions(execId: String, checker: @escaping (String) -> Bool) {
        permissionCheckers[execId] = checker
    }

    /// Unregister the permission checker after execution completes.
    func unregisterPermissions(execId: String) {
        permissionCheckers.removeValue(forKey: execId)
    }

    // MARK: - WKScriptMessageHandlerWithReply

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        Task { @MainActor in
            guard let body = message.body as? [String: Any],
                  let action = body["action"] as? String,
                  let args = body["args"] as? [String: Any] else {
                replyHandler(nil, "Invalid bridge call: expected {action, args}")
                return
            }

            let execId = body["execId"] as? String

            // Native-layer permission check (defense-in-depth)
            if let execId, let checker = permissionCheckers[execId], !checker(action) {
                os_log(.info, log: bridgeLog, "[Bridge] BLOCKED action=%{public}@ execId=%{public}@", action, execId)
                replyHandler("[Error] Action '\(action)' is not permitted for this agent.", nil)
                return
            }

            os_log(.info, log: bridgeLog, "[Bridge] action=%{public}@", action)
            let result = await dispatch(action: action, args: args)
            replyHandler(result, nil)
        }
    }

    // MARK: - Dispatch

    private func dispatch(action: String, args: [String: Any]) async -> String {
        switch action {

        // --- Calendar ---
        case "calendar.listCalendars":
            return await AppleCalendarTools().listCalendars(arguments: args)
        case "calendar.createEvent":
            return await AppleCalendarTools().createEvent(arguments: args)
        case "calendar.searchEvents":
            return await AppleCalendarTools().searchEvents(arguments: args)
        case "calendar.updateEvent":
            return await AppleCalendarTools().updateEvent(arguments: args)
        case "calendar.deleteEvent":
            return await AppleCalendarTools().deleteEvent(arguments: args)

        // --- Reminders ---
        case "reminders.list":
            return await AppleReminderTools().listReminders(arguments: args)
        case "reminders.lists":
            return await AppleReminderTools().listReminderLists(arguments: args)
        case "reminders.create":
            return await AppleReminderTools().createReminder(arguments: args)
        case "reminders.complete":
            return await AppleReminderTools().completeReminder(arguments: args)
        case "reminders.delete":
            return await AppleReminderTools().deleteReminder(arguments: args)

        // --- Contacts ---
        case "contacts.search":
            return await AppleContactsTools().searchContacts(arguments: args)
        case "contacts.getDetail":
            return await AppleContactsTools().getContactDetail(arguments: args)

        // --- Clipboard ---
        case "clipboard.read":
            return await MainActor.run { AppleClipboardTools().readClipboard(arguments: args) }
        case "clipboard.write":
            return await MainActor.run { AppleClipboardTools().writeClipboard(arguments: args) }

        // --- Notifications ---
        case "notifications.schedule":
            return await AppleNotificationTools().scheduleNotification(arguments: args)
        case "notifications.cancel":
            return await AppleNotificationTools().cancelNotification(arguments: args)
        case "notifications.list":
            return await AppleNotificationTools().listNotifications(arguments: args)

        // --- Location ---
        case "location.getCurrent":
            return await AppleLocationTools().getCurrentLocation(arguments: args)
        case "location.geocode":
            return await AppleLocationTools().geocode(arguments: args)
        case "location.reverseGeocode":
            return await AppleLocationTools().reverseGeocode(arguments: args)

        // --- Maps ---
        case "maps.searchPlaces":
            return await AppleMapTools().searchPlaces(arguments: args)
        case "maps.getDirections":
            return await AppleMapTools().getDirections(arguments: args)

        // --- Health (Read) ---
        case "health.readSteps":
            return await AppleHealthTools().readSteps(arguments: args)
        case "health.readHeartRate":
            return await AppleHealthTools().readHeartRate(arguments: args)
        case "health.readSleep":
            return await AppleHealthTools().readSleep(arguments: args)
        case "health.readBodyMass":
            return await AppleHealthTools().readBodyMass(arguments: args)
        case "health.readBloodPressure":
            return await AppleHealthTools().readBloodPressure(arguments: args)
        case "health.readBloodGlucose":
            return await AppleHealthTools().readBloodGlucose(arguments: args)
        case "health.readBloodOxygen":
            return await AppleHealthTools().readBloodOxygen(arguments: args)
        case "health.readBodyTemperature":
            return await AppleHealthTools().readBodyTemperature(arguments: args)
        // --- Health (Write) ---
        case "health.writeDietaryEnergy":
            return await AppleHealthTools().writeDietaryEnergy(arguments: args)
        case "health.writeBodyMass":
            return await AppleHealthTools().writeBodyMass(arguments: args)
        case "health.writeDietaryWater":
            return await AppleHealthTools().writeDietaryWater(arguments: args)
        case "health.writeDietaryCarbohydrates":
            return await AppleHealthTools().writeDietaryCarbohydrates(arguments: args)
        case "health.writeDietaryProtein":
            return await AppleHealthTools().writeDietaryProtein(arguments: args)
        case "health.writeDietaryFat":
            return await AppleHealthTools().writeDietaryFat(arguments: args)
        case "health.writeBloodPressure":
            return await AppleHealthTools().writeBloodPressure(arguments: args)
        case "health.writeBodyFat":
            return await AppleHealthTools().writeBodyFat(arguments: args)
        case "health.writeHeight":
            return await AppleHealthTools().writeHeight(arguments: args)
        case "health.writeBloodGlucose":
            return await AppleHealthTools().writeBloodGlucose(arguments: args)
        case "health.writeBloodOxygen":
            return await AppleHealthTools().writeBloodOxygen(arguments: args)
        case "health.writeBodyTemperature":
            return await AppleHealthTools().writeBodyTemperature(arguments: args)
        case "health.writeHeartRate":
            return await AppleHealthTools().writeHeartRate(arguments: args)
        case "health.writeWorkout":
            return await AppleHealthTools().writeWorkout(arguments: args)

        default:
            return "[Error] Unknown bridge action: \(action)"
        }
    }

    // MARK: - JavaScript Preamble

    /// Generate a JS preamble for the `apple.*` API with per-execution permission enforcement.
    ///
    /// - Parameters:
    ///   - blockedActions: Set of bridge action names to block (e.g. `{"calendar.createEvent", "health.writeBodyMass"}`).
    ///   - execId: Unique execution ID included in every bridge call for native-side permission verification.
    nonisolated static func jsPreamble(blockedActions: Set<String>, execId: String) -> String {
        let blockedArray = blockedActions.map { "'\($0)'" }.joined(separator: ",")
        return """
        var apple = (function() {
            var __blockedActions = new Set([\(blockedArray)]);
            var __execId = '\(execId)';

            async function call(action, args) {
                if (__blockedActions.has(action)) {
                    return '[Error] Action \\'' + action + '\\' is not permitted for this agent.';
                }
                try {
                    return await window.webkit.messageHandlers.appleBridge.postMessage({action: action, args: args || {}, execId: __execId});
                } catch(e) {
                    return '[Error] Bridge call failed: ' + e.message;
                }
            }

            return {
                calendar: {
                    listCalendars: function() { return call('calendar.listCalendars', {}); },
                    createEvent: function(opts) { return call('calendar.createEvent', opts); },
                    searchEvents: function(opts) { return call('calendar.searchEvents', opts || {}); },
                    updateEvent: function(opts) { return call('calendar.updateEvent', opts); },
                    deleteEvent: function(eventId) { return call('calendar.deleteEvent', {event_id: eventId}); }
                },
                reminders: {
                    list: function(opts) { return call('reminders.list', opts || {}); },
                    lists: function() { return call('reminders.lists', {}); },
                    create: function(opts) { return call('reminders.create', opts); },
                    complete: function(reminderId, completed) {
                        return call('reminders.complete', {reminder_id: reminderId, completed: completed !== false});
                    },
                    delete: function(reminderId) { return call('reminders.delete', {reminder_id: reminderId}); }
                },
                contacts: {
                    search: function(query) { return call('contacts.search', {query: query}); },
                    getDetail: function(contactId) { return call('contacts.getDetail', {contact_id: contactId}); }
                },
                clipboard: {
                    read: function() { return call('clipboard.read', {}); },
                    write: function(text) { return call('clipboard.write', {text: text}); }
                },
                notifications: {
                    schedule: function(opts) { return call('notifications.schedule', opts); },
                    cancel: function(id) { return call('notifications.cancel', {id: id}); },
                    cancelAll: function() { return call('notifications.cancel', {cancel_all: true}); },
                    list: function() { return call('notifications.list', {}); }
                },
                location: {
                    getCurrent: function(includeAddress) {
                        return call('location.getCurrent', {include_address: includeAddress !== false});
                    },
                    geocode: function(address) { return call('location.geocode', {address: address}); },
                    reverseGeocode: function(lat, lon) {
                        return call('location.reverseGeocode', {latitude: lat, longitude: lon});
                    }
                },
                maps: {
                    searchPlaces: function(query, opts) {
                        var args = opts || {};
                        args.query = query;
                        return call('maps.searchPlaces', args);
                    },
                    getDirections: function(opts) { return call('maps.getDirections', opts); }
                },
                health: {
                    readSteps: function(opts) { return call('health.readSteps', opts || {}); },
                    readHeartRate: function(opts) { return call('health.readHeartRate', opts || {}); },
                    readSleep: function(opts) { return call('health.readSleep', opts || {}); },
                    readBodyMass: function(opts) { return call('health.readBodyMass', opts || {}); },
                    readBloodPressure: function(opts) { return call('health.readBloodPressure', opts || {}); },
                    readBloodGlucose: function(opts) { return call('health.readBloodGlucose', opts || {}); },
                    readBloodOxygen: function(opts) { return call('health.readBloodOxygen', opts || {}); },
                    readBodyTemperature: function(opts) { return call('health.readBodyTemperature', opts || {}); },
                    writeDietaryEnergy: function(opts) { return call('health.writeDietaryEnergy', opts || {}); },
                    writeBodyMass: function(opts) { return call('health.writeBodyMass', opts || {}); },
                    writeDietaryWater: function(opts) { return call('health.writeDietaryWater', opts || {}); },
                    writeDietaryCarbohydrates: function(opts) { return call('health.writeDietaryCarbohydrates', opts || {}); },
                    writeDietaryProtein: function(opts) { return call('health.writeDietaryProtein', opts || {}); },
                    writeDietaryFat: function(opts) { return call('health.writeDietaryFat', opts || {}); },
                    writeBloodPressure: function(opts) { return call('health.writeBloodPressure', opts || {}); },
                    writeBodyFat: function(opts) { return call('health.writeBodyFat', opts || {}); },
                    writeHeight: function(opts) { return call('health.writeHeight', opts || {}); },
                    writeBloodGlucose: function(opts) { return call('health.writeBloodGlucose', opts || {}); },
                    writeBloodOxygen: function(opts) { return call('health.writeBloodOxygen', opts || {}); },
                    writeBodyTemperature: function(opts) { return call('health.writeBodyTemperature', opts || {}); },
                    writeHeartRate: function(opts) { return call('health.writeHeartRate', opts || {}); },
                    writeWorkout: function(opts) { return call('health.writeWorkout', opts || {}); }
                }
            };
        })();
        """
    }

    /// Convenience: preamble with no restrictions (backward compatible for non-agent contexts).
    nonisolated static var jsPreambleUnrestricted: String {
        jsPreamble(blockedActions: [], execId: "")
    }
}
