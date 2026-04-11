import Foundation

/// Orchestrates the Live Activity background keep-alive strategy based on
/// the user's preference.
///
/// Tracks all active sessions (chat generations, cron jobs, sub-agents) and
/// manages the Dynamic Island / Lock Screen Live Activity accordingly.
///
/// The feature is persisted as a boolean in `UserDefaults` and is **off** by
/// default.
@MainActor
final class BackgroundKeepAliveManager {

    nonisolated static let enabledKey = "backgroundKeepAliveEnabled"

    private let liveActivityManager = CronLiveActivityManager()

    /// Active session IDs currently running.
    private var activeSessions: Set<UUID> = []
    /// Maps active session IDs to their display names.
    private var sessionNames: [UUID: String] = [:]
    /// Index for rotating through session names in the Live Activity.
    private var rotationIndex: Int = 0
    /// Timer for rotating session names in the Dynamic Island.
    private var rotationTimer: Timer?
    /// Whether the app is currently in the background.
    private var isInBackground = false
    /// Whether any new tasks were started while the app was in background.
    private var hadNewTasksDuringBackground = false
    /// Name and error state of the last completed session (persists until new task starts).
    private var lastCompletionName: String?
    private var lastCompletionIsError: Bool = false
    /// Whether we are currently showing a completion status.
    private var isShowingCompletion = false

    /// Whether the Live Activity keep-alive is enabled (read from UserDefaults).
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if !newValue { forceDeactivate() }
        }
    }

    // MARK: - Lifecycle

    /// Called when the app moves to background.
    func activate() {
        isInBackground = true
        hadNewTasksDuringBackground = false
        guard isEnabled else { return }
        if !activeSessions.isEmpty {
            startOrUpdateActivity()
        } else {
            // No active tasks — start a keep-alive activity anyway
            liveActivityManager.start(
                activeAgentCount: 0,
                sessionName: "",
                statusText: L10n.LiveActivity.running
            )
        }
    }

    /// Called when the app returns to foreground.
    func onReturnToForeground() {
        isInBackground = false
        stopRotationTimer()
        if activeSessions.isEmpty && !hadNewTasksDuringBackground {
            // No tasks ran during background and nothing active now — dismiss
            liveActivityManager.stop()
            clearCompletion()
        }
        // If tasks are still active, keep the Live Activity visible
    }

    /// Force-stop the Live Activity (used when user disables the feature).
    private func forceDeactivate() {
        stopRotationTimer()
        liveActivityManager.stop()
        clearCompletion()
    }

    // MARK: - Session Tracking

    /// Called when any agent task starts (chat, cron, sub-agent).
    func onSessionStarted(sessionId: UUID, sessionName: String) {
        activeSessions.insert(sessionId)
        sessionNames[sessionId] = sessionName

        if isInBackground {
            hadNewTasksDuringBackground = true
        }

        // Clear completion status when a new task starts
        clearCompletion()

        guard isEnabled else { return }
        startOrUpdateActivity()
    }

    /// Called when any agent task completes.
    func onSessionCompleted(sessionId: UUID, sessionName: String, isError: Bool) {
        activeSessions.remove(sessionId)
        sessionNames.removeValue(forKey: sessionId)

        guard isEnabled else { return }

        if activeSessions.isEmpty {
            // All tasks done — show completion status
            stopRotationTimer()
            lastCompletionName = sessionName
            lastCompletionIsError = isError
            isShowingCompletion = true
            liveActivityManager.showCompletionStatus(sessionName: sessionName, isError: isError)
        } else {
            // Other tasks still running — update the count
            startOrUpdateActivity()
        }
    }

    // MARK: - Internal

    private func startOrUpdateActivity() {
        let count = activeSessions.count
        let name = currentRotationName()

        let statusText: String
        if count > 0 {
            statusText = L10n.LiveActivity.agentsRunning(count)
        } else {
            statusText = L10n.LiveActivity.running
        }

        if liveActivityManager.isActive {
            liveActivityManager.update(
                activeAgentCount: count,
                sessionName: name,
                statusText: statusText
            )
        } else {
            liveActivityManager.start(
                activeAgentCount: max(count, 1),
                sessionName: name,
                statusText: statusText
            )
        }

        // Start rotation timer if multiple sessions
        if count > 1 && rotationTimer == nil {
            startRotationTimer()
        } else if count <= 1 {
            stopRotationTimer()
        }
    }

    /// Returns the session name for the current rotation index.
    private func currentRotationName() -> String {
        let names = Array(sessionNames.values)
        guard !names.isEmpty else { return "" }
        let index = rotationIndex % names.count
        return names[index]
    }

    private func startRotationTimer() {
        rotationTimer?.invalidate()
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.rotateSessionName()
            }
        }
    }

    private func stopRotationTimer() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        rotationIndex = 0
    }

    private func rotateSessionName() {
        guard !activeSessions.isEmpty else { return }
        rotationIndex += 1
        startOrUpdateActivity()
    }

    private func clearCompletion() {
        lastCompletionName = nil
        lastCompletionIsError = false
        isShowingCompletion = false
    }
}
