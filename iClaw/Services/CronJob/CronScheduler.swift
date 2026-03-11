import Foundation
import SwiftData
import BackgroundTasks

@Observable
@MainActor
final class CronScheduler {
    static let bgTaskIdentifier = "com.iclaw.cronjob.refresh"
    private static let checkInterval: TimeInterval = 30

    private(set) var isRunning = false
    private(set) var lastCheckDate: Date?
    private(set) var runningJobIds: Set<UUID> = []

    private let modelContainer: ModelContainer
    private var timer: Timer?
    private let executor: CronExecutor

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.executor = CronExecutor(modelContainer: modelContainer)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        timer = Timer.scheduledTimer(
            withTimeInterval: Self.checkInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.tick()
            }
        }
        timer?.tolerance = 5

        Task { await tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func rescheduleAll() {
        Task { await updateNextRunDates() }
    }

    // MARK: - Background Task

    nonisolated func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    nonisolated func handleBackgroundTask(_ task: BGAppRefreshTask) {
        scheduleBackgroundTask()

        let context = ModelContext(modelContainer)
        let bgExecutor = CronExecutor(modelContainer: modelContainer)

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task {
            let jobs = Self.fetchDueJobs(context: context, now: Date())

            for job in jobs {
                guard let agent = job.agent else { continue }
                await bgExecutor.executeJob(job, agent: agent, context: context)
            }

            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - Core Loop

    private func tick() async {
        let now = Date()
        lastCheckDate = now

        let context = ModelContext(modelContainer)
        let dueJobs = Self.fetchDueJobs(context: context, now: now)

        for job in dueJobs {
            guard !runningJobIds.contains(job.id) else { continue }
            guard let agent = job.agent else { continue }

            runningJobIds.insert(job.id)

            let jobId = job.id
            Task {
                await executor.executeJob(job, agent: agent, context: context)
                await MainActor.run {
                    runningJobIds.remove(jobId)
                }
            }
        }
    }

    private func updateNextRunDates() async {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CronJob>(
            predicate: #Predicate { $0.isEnabled == true }
        )
        guard let jobs = try? context.fetch(descriptor) else { return }

        let now = Date()
        for job in jobs {
            if let next = try? CronParser.nextFireDate(after: now, for: job.cronExpression) {
                job.nextRunAt = next
            }
        }
        try? context.save()
    }

    nonisolated static func fetchDueJobs(context: ModelContext, now: Date) -> [CronJob] {
        let descriptor = FetchDescriptor<CronJob>(
            predicate: #Predicate { $0.isEnabled == true }
        )
        guard let jobs = try? context.fetch(descriptor) else { return [] }

        return jobs.filter { job in
            guard let nextRun = job.nextRunAt else {
                // Never scheduled — compute and check
                if let computed = try? CronParser.nextFireDate(after: job.createdAt, for: job.cronExpression) {
                    return computed <= now
                }
                return false
            }
            return nextRun <= now
        }
    }
}
