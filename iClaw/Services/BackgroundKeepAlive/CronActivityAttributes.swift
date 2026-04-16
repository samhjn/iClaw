import ActivityKit
import Foundation

/// Defines the static and dynamic data for the background-task Live Activity
/// shown on the Lock Screen and Dynamic Island.
struct CronActivityAttributes: ActivityAttributes {
    /// Fixed context supplied when the activity is requested.
    struct ContentState: Codable, Hashable {
        /// Number of agents currently executing tasks.
        var activeAgentCount: Int
        /// Name of the currently displayed session (rotated externally when multiple).
        var sessionName: String
        /// Descriptive status text (e.g. "2 Agents running").
        var statusText: String
        /// Whether the last completed task finished successfully.
        var isCompleted: Bool = false
        /// Whether the last completed task finished with an error.
        var isError: Bool = false
        /// Short, pre-localized status brief mirroring the silent-mode progress
        /// (e.g. "Thinking (round 2)", "Browse"). Empty when no in-flight activity.
        var statusBrief: String = ""
        /// SF Symbol name for the accompanying brief icon (e.g. "globe", "brain.head.profile").
        var statusBriefIcon: String = ""
    }
}
