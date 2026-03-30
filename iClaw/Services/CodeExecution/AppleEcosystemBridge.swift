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
/// The bridge installs two global objects:
/// - `fs` — standalone file system API: `fs.list()`, `fs.read()`, `fs.write()`, `fs.delete()`, `fs.info()`
/// - `apple` — Apple ecosystem APIs: `apple.calendar.*`, `apple.reminders.*`, `apple.contacts.*`,
///   `apple.clipboard.*`, `apple.notifications.*`, `apple.location.*`, `apple.maps.*`, `apple.health.*`
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

    /// Execution contexts keyed by execution ID.
    /// Each JS execution registers a context before running and removes it after.
    private var executionContexts: [String: ExecutionContext] = [:]

    struct ExecutionContext {
        let permissionChecker: (String) -> Bool
        let agentId: UUID?
    }

    /// Permission checkers keyed by execution ID (legacy accessor).
    private var permissionCheckers: [String: (String) -> Bool] {
        executionContexts.mapValues { $0.permissionChecker }
    }

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
        executionContexts[execId] = ExecutionContext(permissionChecker: checker, agentId: nil)
    }

    /// Register a full execution context with permissions and agent ID (for file operations).
    func registerContext(execId: String, agentId: UUID?, checker: @escaping (String) -> Bool) {
        executionContexts[execId] = ExecutionContext(permissionChecker: checker, agentId: agentId)
    }

    /// Unregister the execution context after completion.
    func unregisterPermissions(execId: String) {
        executionContexts.removeValue(forKey: execId)
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
            let ctx = execId.flatMap { executionContexts[$0] }
            if let execId, let ctx, !ctx.permissionChecker(action) {
                os_log(.info, log: bridgeLog, "[Bridge] BLOCKED action=%{public}@ execId=%{public}@", action, execId)
                replyHandler("[Error] Action '\(action)' is not permitted for this agent.", nil)
                return
            }

            os_log(.info, log: bridgeLog, "[Bridge] action=%{public}@", action)
            let result = await dispatch(action: action, args: args, context: ctx)
            replyHandler(result, nil)
        }
    }

    // MARK: - Dispatch

    private func dispatch(action: String, args: [String: Any], context: ExecutionContext? = nil) async -> String {
        switch action {

        // --- Files ---
        case "files.list":
            guard let agentId = context?.agentId else { return "[Error] No agent context for file operations." }
            let files = AgentFileManager.shared.listFiles(agentId: agentId)
            if files.isEmpty { return "[]" }
            let items = files.map { "{\"name\":\"\($0.name)\",\"size\":\($0.size),\"is_image\":\($0.isImage)}" }
            return "[\(items.joined(separator: ","))]"
        case "files.read":
            guard let agentId = context?.agentId else { return "[Error] No agent context for file operations." }
            guard let name = args["name"] as? String else { return "[Error] Missing 'name' argument." }
            let mode = args["mode"] as? String ?? "text"
            do {
                let data = try AgentFileManager.shared.readFile(agentId: agentId, name: name)
                if mode == "base64" { return data.base64EncodedString() }
                return String(data: data, encoding: .utf8) ?? "[Error] Binary file; use mode='base64'."
            } catch { return "[Error] \(error.localizedDescription)" }
        case "files.write":
            guard let agentId = context?.agentId else { return "[Error] No agent context for file operations." }
            guard let name = args["name"] as? String else { return "[Error] Missing 'name' argument." }
            let content = args["content"] as? String ?? ""
            let encoding = args["encoding"] as? String ?? "text"
            let data: Data
            if encoding == "base64" {
                guard let d = Data(base64Encoded: content, options: .ignoreUnknownCharacters) else { return "[Error] Invalid base64." }
                data = d
            } else { data = Data(content.utf8) }
            do { try AgentFileManager.shared.writeFile(agentId: agentId, name: name, data: data); return "OK" }
            catch { return "[Error] \(error.localizedDescription)" }
        case "files.delete":
            guard let agentId = context?.agentId else { return "[Error] No agent context for file operations." }
            guard let name = args["name"] as? String else { return "[Error] Missing 'name' argument." }
            do { try AgentFileManager.shared.deleteFile(agentId: agentId, name: name); return "OK" }
            catch { return "[Error] \(error.localizedDescription)" }
        case "files.info":
            guard let agentId = context?.agentId else { return "[Error] No agent context for file operations." }
            guard let name = args["name"] as? String else { return "[Error] Missing 'name' argument." }
            guard let info = AgentFileManager.shared.fileInfo(agentId: agentId, name: name) else { return "[Error] File not found." }
            return "{\"name\":\"\(info.name)\",\"size\":\(info.size),\"is_image\":\(info.isImage)}"

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
        var __blockedActions = new Set([\(blockedArray)]);
        var __execId = '\(execId)';

        async function __bridgeCall(action, args) {
            if (__blockedActions.has(action)) {
                return '[Error] Action \\'' + action + '\\' is not permitted for this agent.';
            }
            try {
                return await window.webkit.messageHandlers.appleBridge.postMessage({action: action, args: args || {}, execId: __execId});
            } catch(e) {
                return '[Error] Bridge call failed: ' + e.message;
            }
        }

        var fs = {
            list: function() { return __bridgeCall('files.list', {}); },
            read: function(name, opts) { var a = opts || {}; a.name = name; return __bridgeCall('files.read', a); },
            write: function(name, content, opts) { var a = opts || {}; a.name = name; a.content = content; return __bridgeCall('files.write', a); },
            delete: function(name) { return __bridgeCall('files.delete', {name: name}); },
            info: function(name) { return __bridgeCall('files.info', {name: name}); }
        };

        var apple = (function() {
            return {
                calendar: {
                    listCalendars: function() { return __bridgeCall('calendar.listCalendars', {}); },
                    createEvent: function(opts) { return __bridgeCall('calendar.createEvent', opts); },
                    searchEvents: function(opts) { return __bridgeCall('calendar.searchEvents', opts || {}); },
                    updateEvent: function(opts) { return __bridgeCall('calendar.updateEvent', opts); },
                    deleteEvent: function(eventId) { return __bridgeCall('calendar.deleteEvent', {event_id: eventId}); }
                },
                reminders: {
                    list: function(opts) { return __bridgeCall('reminders.list', opts || {}); },
                    lists: function() { return __bridgeCall('reminders.lists', {}); },
                    create: function(opts) { return __bridgeCall('reminders.create', opts); },
                    complete: function(reminderId, completed) {
                        return __bridgeCall('reminders.complete', {reminder_id: reminderId, completed: completed !== false});
                    },
                    delete: function(reminderId) { return __bridgeCall('reminders.delete', {reminder_id: reminderId}); }
                },
                contacts: {
                    search: function(query) { return __bridgeCall('contacts.search', {query: query}); },
                    getDetail: function(contactId) { return __bridgeCall('contacts.getDetail', {contact_id: contactId}); }
                },
                clipboard: {
                    read: function() { return __bridgeCall('clipboard.read', {}); },
                    write: function(text) { return __bridgeCall('clipboard.write', {text: text}); }
                },
                notifications: {
                    schedule: function(opts) { return __bridgeCall('notifications.schedule', opts); },
                    cancel: function(id) { return __bridgeCall('notifications.cancel', {id: id}); },
                    cancelAll: function() { return __bridgeCall('notifications.cancel', {cancel_all: true}); },
                    list: function() { return __bridgeCall('notifications.list', {}); }
                },
                location: {
                    getCurrent: function(includeAddress) {
                        return __bridgeCall('location.getCurrent', {include_address: includeAddress !== false});
                    },
                    geocode: function(address) { return __bridgeCall('location.geocode', {address: address}); },
                    reverseGeocode: function(lat, lon) {
                        return __bridgeCall('location.reverseGeocode', {latitude: lat, longitude: lon});
                    }
                },
                maps: {
                    searchPlaces: function(query, opts) {
                        var args = opts || {};
                        args.query = query;
                        return __bridgeCall('maps.searchPlaces', args);
                    },
                    getDirections: function(opts) { return __bridgeCall('maps.getDirections', opts); }
                },
                health: {
                    readSteps: function(opts) { return __bridgeCall('health.readSteps', opts || {}); },
                    readHeartRate: function(opts) { return __bridgeCall('health.readHeartRate', opts || {}); },
                    readSleep: function(opts) { return __bridgeCall('health.readSleep', opts || {}); },
                    readBodyMass: function(opts) { return __bridgeCall('health.readBodyMass', opts || {}); },
                    readBloodPressure: function(opts) { return __bridgeCall('health.readBloodPressure', opts || {}); },
                    readBloodGlucose: function(opts) { return __bridgeCall('health.readBloodGlucose', opts || {}); },
                    readBloodOxygen: function(opts) { return __bridgeCall('health.readBloodOxygen', opts || {}); },
                    readBodyTemperature: function(opts) { return __bridgeCall('health.readBodyTemperature', opts || {}); },
                    writeDietaryEnergy: function(opts) { return __bridgeCall('health.writeDietaryEnergy', opts || {}); },
                    writeBodyMass: function(opts) { return __bridgeCall('health.writeBodyMass', opts || {}); },
                    writeDietaryWater: function(opts) { return __bridgeCall('health.writeDietaryWater', opts || {}); },
                    writeDietaryCarbohydrates: function(opts) { return __bridgeCall('health.writeDietaryCarbohydrates', opts || {}); },
                    writeDietaryProtein: function(opts) { return __bridgeCall('health.writeDietaryProtein', opts || {}); },
                    writeDietaryFat: function(opts) { return __bridgeCall('health.writeDietaryFat', opts || {}); },
                    writeBloodPressure: function(opts) { return __bridgeCall('health.writeBloodPressure', opts || {}); },
                    writeBodyFat: function(opts) { return __bridgeCall('health.writeBodyFat', opts || {}); },
                    writeHeight: function(opts) { return __bridgeCall('health.writeHeight', opts || {}); },
                    writeBloodGlucose: function(opts) { return __bridgeCall('health.writeBloodGlucose', opts || {}); },
                    writeBloodOxygen: function(opts) { return __bridgeCall('health.writeBloodOxygen', opts || {}); },
                    writeBodyTemperature: function(opts) { return __bridgeCall('health.writeBodyTemperature', opts || {}); },
                    writeHeartRate: function(opts) { return __bridgeCall('health.writeHeartRate', opts || {}); },
                    writeWorkout: function(opts) { return __bridgeCall('health.writeWorkout', opts || {}); }
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
