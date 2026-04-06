import Foundation
import BackgroundTasks

/// Abstraction over `BGTaskScheduler` to enable unit testing of registration lifecycle.
protocol BGTaskRegistering {
    @discardableResult
    func register(
        forTaskWithIdentifier identifier: String,
        using queue: DispatchQueue?,
        launchHandler: @escaping @Sendable (BGTask) -> Void
    ) -> Bool
}

extension BGTaskScheduler: BGTaskRegistering {}

/// Coordinates BGTask registration with `CronScheduler` lifecycle.
///
/// Registration **must** happen during app launch (`App.init`). The scheduler
/// is created later (in `onAppear`) and linked via the ``scheduler`` property.
/// Separating these two phases prevents the `BGTaskScheduler` assertion failure
/// that occurs when `register(forTaskWithIdentifier:)` is called after launch.
final class CronBGTaskCoordinator: @unchecked Sendable {
    private(set) var isRegistered = false
    var scheduler: CronScheduler?
    private let registrar: any BGTaskRegistering

    init(registrar: any BGTaskRegistering = BGTaskScheduler.shared) {
        self.registrar = registrar
    }

    /// Register the cron background refresh task.
    ///
    /// - Returns: `false` if already registered or if the system rejected the registration.
    @discardableResult
    func registerCronTask() -> Bool {
        guard !isRegistered else { return false }
        let registered = registrar.register(
            forTaskWithIdentifier: CronScheduler.bgTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                guard let scheduler = self?.scheduler else {
                    task.setTaskCompleted(success: false)
                    return
                }
                scheduler.handleBackgroundTask(refreshTask)
            }
        }
        isRegistered = registered
        return registered
    }
}
