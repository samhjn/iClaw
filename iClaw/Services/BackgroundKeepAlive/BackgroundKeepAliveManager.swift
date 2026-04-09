import Foundation

/// The user-selectable strategy for enhanced background execution.
enum BackgroundKeepAliveMode: String, CaseIterable, Identifiable {
    /// No enhanced background execution (system default).
    case off
    /// Play an inaudible audio track to prevent suspension.
    case silentAudio
    /// Pin a Live Activity to the Dynamic Island / Lock Screen.
    case liveActivity

    var id: String { rawValue }
}

/// Orchestrates background keep-alive strategies based on the user's preference.
///
/// The selected mode is persisted in `UserDefaults` and is **off** by default.
/// Call `activate()` / `deactivate()` when the app enters background / foreground,
/// and `onJobsChanged(runningCount:)` whenever the number of active cron jobs changes.
@MainActor
final class BackgroundKeepAliveManager {

    nonisolated static let modeKey = "backgroundKeepAliveMode"
    nonisolated static let appGroupID = "group.com.iclaw.app"

    private let silentPlayer = SilentAudioPlayer()
    private let liveActivityManager = CronLiveActivityManager()

    /// Shared UserDefaults accessible by both the main app and the widget extension.
    private nonisolated static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// The currently configured mode (read from shared App Group UserDefaults).
    var mode: BackgroundKeepAliveMode {
        get {
            guard let raw = Self.sharedDefaults.string(forKey: Self.modeKey),
                  let m = BackgroundKeepAliveMode(rawValue: raw) else {
                return .off
            }
            return m
        }
        set {
            Self.sharedDefaults.set(newValue.rawValue, forKey: Self.modeKey)
            // If the user just switched mode, tear down the previous strategy
            deactivate()
        }
    }

    // MARK: - Lifecycle

    /// Called when the app moves to background **and** there are scheduled cron jobs.
    func activate(runningJobCount: Int = 0) {
        switch mode {
        case .off:
            break
        case .silentAudio:
            silentPlayer.start()
        case .liveActivity:
            liveActivityManager.start(runningJobCount: max(runningJobCount, 1))
        }
    }

    /// Called when the app returns to foreground or the user disables the feature.
    func deactivate() {
        silentPlayer.stop()
        liveActivityManager.stop()
    }

    /// Notify the manager that the running job count has changed so it can
    /// update the Live Activity badge or decide whether to keep audio alive.
    func onJobsChanged(runningCount: Int) {
        switch mode {
        case .off:
            break
        case .silentAudio:
            if runningCount > 0 {
                silentPlayer.start()
            }
            // Keep audio running even when runningCount drops to 0 — the user
            // opted in for continuous background, we stop on foreground entry.
        case .liveActivity:
            if runningCount > 0 {
                liveActivityManager.update(runningJobCount: runningCount)
            } else {
                liveActivityManager.stop()
            }
        }
    }
}
