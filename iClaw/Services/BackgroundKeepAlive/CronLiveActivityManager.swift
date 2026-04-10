import ActivityKit
import Foundation

/// Manages a Live Activity that appears on the Dynamic Island / Lock Screen
/// while cron jobs are running, giving the system a reason to keep the app
/// active and providing the user with at-a-glance status.
@MainActor
final class CronLiveActivityManager {

    private var currentActivity: Activity<CronActivityAttributes>?
    private(set) var isActive = false

    /// Starts (or updates) the Live Activity with the current job count.
    func start(runningJobCount: Int = 1, statusText: String? = nil) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[CronLiveActivity] Live Activities are not enabled")
            return
        }

        let state = CronActivityAttributes.ContentState(
            runningJobCount: runningJobCount,
            statusText: statusText ?? NSLocalizedString("cronLiveActivity.running", comment: "")
        )

        if let existing = currentActivity {
            // Update existing activity
            Task {
                await existing.update(
                    ActivityContent(state: state, staleDate: nil)
                )
            }
            return
        }

        // Start a new activity
        let attributes = CronActivityAttributes()
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            isActive = true
            print("[CronLiveActivity] Started activity")
        } catch {
            print("[CronLiveActivity] Failed to start: \(error)")
        }
    }

    /// Updates the running job count on an existing activity.
    func update(runningJobCount: Int, statusText: String? = nil) {
        guard let activity = currentActivity else { return }
        let state = CronActivityAttributes.ContentState(
            runningJobCount: runningJobCount,
            statusText: statusText ?? NSLocalizedString("cronLiveActivity.running", comment: "")
        )
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: nil)
            )
        }
    }

    /// Ends the Live Activity (e.g. when all jobs finish or the user disables the feature).
    func stop() {
        guard let activity = currentActivity else { return }
        let finalState = CronActivityAttributes.ContentState(
            runningJobCount: 0,
            statusText: NSLocalizedString("cronLiveActivity.done", comment: "")
        )
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        currentActivity = nil
        isActive = false
        print("[CronLiveActivity] Stopped activity")
    }
}
