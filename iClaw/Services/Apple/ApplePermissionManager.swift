import Foundation
import EventKit
import Contacts
import CoreLocation
import UserNotifications
import HealthKit

/// Centralized permission manager for Apple ecosystem APIs.
final class ApplePermissionManager {
    static let shared = ApplePermissionManager()
    private init() {}

    // Shared stores
    let eventStore = EKEventStore()
    let contactStore = CNContactStore()
    let healthStore = HKHealthStore()

    // MARK: - Calendar

    func requestCalendarAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    var calendarAuthorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    func ensureCalendarAccess() async -> String? {
        switch calendarAuthorizationStatus {
        case .fullAccess:
            return nil
        case .notDetermined:
            let granted = await requestCalendarAccess()
            return granted ? nil : "[Error] Calendar access denied by user."
        case .denied, .restricted:
            return "[Error] Calendar access denied. Please enable in Settings > Privacy > Calendars."
        case .writeOnly:
            return "[Error] Only write access granted. Full access is required. Please update in Settings > Privacy > Calendars."
        @unknown default:
            return "[Error] Unknown calendar authorization status."
        }
    }

    // MARK: - Reminders

    func requestRemindersAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    var remindersAuthorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    func ensureRemindersAccess() async -> String? {
        switch remindersAuthorizationStatus {
        case .fullAccess:
            return nil
        case .notDetermined:
            let granted = await requestRemindersAccess()
            return granted ? nil : "[Error] Reminders access denied by user."
        case .denied, .restricted:
            return "[Error] Reminders access denied. Please enable in Settings > Privacy > Reminders."
        default:
            return "[Error] Unknown reminders authorization status."
        }
    }

    // MARK: - Contacts

    func requestContactsAccess() async -> Bool {
        do {
            return try await contactStore.requestAccess(for: .contacts)
        } catch {
            return false
        }
    }

    var contactsAuthorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    func ensureContactsAccess() async -> String? {
        switch contactsAuthorizationStatus {
        case .authorized:
            return nil
        case .notDetermined:
            let granted = await requestContactsAccess()
            return granted ? nil : "[Error] Contacts access denied by user."
        case .denied, .restricted:
            return "[Error] Contacts access denied. Please enable in Settings > Privacy > Contacts."
        case .limited:
            return nil
        @unknown default:
            return "[Error] Unknown contacts authorization status."
        }
    }

    // MARK: - Notifications

    func requestNotificationAccess() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func ensureNotificationAccess() async -> String? {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return nil
        case .notDetermined:
            let granted = await requestNotificationAccess()
            return granted ? nil : "[Error] Notification access denied by user."
        case .denied:
            return "[Error] Notification access denied. Please enable in Settings > Notifications."
        @unknown default:
            return "[Error] Unknown notification authorization status."
        }
    }

    // MARK: - Location

    private var locationManagerDelegate: LocationPermissionDelegate?

    @MainActor
    func ensureLocationAccess() async -> String? {
        let manager = CLLocationManager()
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return nil
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                let delegate = LocationPermissionDelegate { status in
                    switch status {
                    case .authorizedWhenInUse, .authorizedAlways:
                        continuation.resume(returning: nil)
                    default:
                        continuation.resume(returning: "[Error] Location access denied by user.")
                    }
                }
                self.locationManagerDelegate = delegate
                manager.delegate = delegate
                manager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            return "[Error] Location access denied. Please enable in Settings > Privacy > Location Services."
        @unknown default:
            return "[Error] Unknown location authorization status."
        }
    }

    // MARK: - Status Summary

    func permissionSummary() -> String {
        let cal = calendarAuthorizationStatus
        let rem = remindersAuthorizationStatus
        let con = contactsAuthorizationStatus
        let loc = CLLocationManager().authorizationStatus

        return """
        Apple Ecosystem Permissions:
        - Calendar: \(describeEKStatus(cal))
        - Reminders: \(describeEKStatus(rem))
        - Contacts: \(describeCNStatus(con))
        - Location: \(describeCLStatus(loc))
        - HealthKit: \(describeHealthAvailability())
        - Notifications: (check async)
        """
    }

    // MARK: - HealthKit

    func ensureHealthAccess(read: Set<HKObjectType>, write: Set<HKSampleType>) async -> String? {
        guard HKHealthStore.isHealthDataAvailable() else {
            return "[Error] Health data is not available on this device."
        }

        do {
            try await healthStore.requestAuthorization(toShare: write, read: read)
            return nil
        } catch {
            return "[Error] Failed to request HealthKit access: \(error.localizedDescription)"
        }
    }

    private func describeEKStatus(_ s: EKAuthorizationStatus) -> String {
        switch s {
        case .fullAccess: return "Full Access"
        case .writeOnly: return "Write Only"
        case .notDetermined: return "Not Determined"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }

    private func describeCNStatus(_ s: CNAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "Authorized"
        case .limited: return "Limited"
        case .notDetermined: return "Not Determined"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }

    private func describeCLStatus(_ s: CLAuthorizationStatus) -> String {
        switch s {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "When In Use"
        case .notDetermined: return "Not Determined"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }

    private func describeHealthAvailability() -> String {
        HKHealthStore.isHealthDataAvailable() ? "Available" : "Unavailable"
    }
}

// MARK: - Location Permission Helper

private final class LocationPermissionDelegate: NSObject, CLLocationManagerDelegate {
    private let completion: (CLAuthorizationStatus) -> Void
    private var didCallBack = false

    init(completion: @escaping (CLAuthorizationStatus) -> Void) {
        self.completion = completion
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !didCallBack, manager.authorizationStatus != .notDetermined else { return }
        didCallBack = true
        completion(manager.authorizationStatus)
    }
}
