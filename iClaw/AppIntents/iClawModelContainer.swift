import Foundation
import SwiftData

/// Single source of truth for the app's SwiftData `ModelContainer`.
///
/// Both `iClawApp` (main process, foreground) and the App Intents
/// (background execution triggered by Shortcuts automations) resolve the
/// same container via `shared`, so cron writes from either path observe
/// identical state without a second store file.
///
/// `static let` is initialized exactly once with `dispatch_once` semantics,
/// so concurrent readers see a consistent instance.
enum iClawModelContainer {
    static let schema = Schema([
        Agent.self,
        AgentConfig.self,
        Session.self,
        Message.self,
        LLMProvider.self,
        CodeSnippet.self,
        CronJob.self,
        Skill.self,
        InstalledSkill.self,
        SessionEmbedding.self,
    ])

    /// When the on-disk store fails to open (typically a SwiftData migration
    /// error), this records the URL of the failed store so `iClawApp` can
    /// offer the user a reset-and-restart. `nil` on success.
    private(set) static var migrationFailedStoreURL: URL?

    static let shared: ModelContainer = {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("[iClawModelContainer] Primary container construction failed: \(error). Falling back to in-memory.")
            migrationFailedStoreURL = config.url
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("Failed to create in-memory ModelContainer: \(error)")
            }
        }
    }()
}
