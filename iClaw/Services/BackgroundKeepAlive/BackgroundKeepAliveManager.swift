import Foundation

/// Orchestrates the Live Activity background keep-alive strategy based on
/// the user's preference.
///
/// The feature is persisted as a boolean in `UserDefaults` and is **off** by
/// default. Call `activate()` / `deactivate()` when the app enters
/// background / foreground, and `onJobsChanged(runningCount:)` whenever
/// the number of active cron jobs changes.
@MainActor
final class BackgroundKeepAliveManager {

    nonisolated static let enabledKey = "backgroundKeepAliveEnabled"

    private let liveActivityManager = CronLiveActivityManager()

    /// Whether the Live Activity keep-alive is enabled (read from UserDefaults).
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if !newValue { deactivate() }
        }
    }

    // MARK: - Lifecycle

    /// Called when the app moves to background.
    func activate(runningJobCount: Int = 0) {
        guard isEnabled else { return }
        liveActivityManager.start(runningJobCount: max(runningJobCount, 1))
    }

    /// Called when the app returns to foreground or the user disables the feature.
    func deactivate() {
        liveActivityManager.stop()
    }

    /// Notify the manager that the running job count has changed so it can
    /// update the Live Activity badge.
    func onJobsChanged(runningCount: Int) {
        guard isEnabled else { return }
        if runningCount > 0 {
            liveActivityManager.update(runningJobCount: runningCount)
        } else {
            liveActivityManager.stop()
        }
    }
}
