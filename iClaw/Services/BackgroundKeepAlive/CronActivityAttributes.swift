import ActivityKit
import Foundation

/// Defines the static and dynamic data for the cron-job Live Activity
/// shown on the Lock Screen and Dynamic Island.
struct CronActivityAttributes: ActivityAttributes {
    /// Fixed context supplied when the activity is requested.
    struct ContentState: Codable, Hashable {
        /// Number of cron jobs currently executing.
        var runningJobCount: Int
        /// Descriptive status text (e.g. "Running daily report…").
        var statusText: String
    }
}
