import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct iClawApp: App {
    let modelContainer: ModelContainer
    @State private var cronScheduler: CronScheduler?

    init() {
        let schema = Schema([
            Agent.self,
            AgentConfig.self,
            Session.self,
            Message.self,
            LLMProvider.self,
            CodeSnippet.self,
            CronJob.self,
            Skill.self,
            InstalledSkill.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema migration failed — delete the old store and recreate
            print("[iClawApp] ModelContainer migration failed: \(error). Deleting old store.")
            let storeURL = config.url
            let related = [
                storeURL,
                storeURL.appendingPathExtension("wal"),
                storeURL.appendingPathExtension("shm"),
            ]
            for url in related {
                try? FileManager.default.removeItem(at: url)
            }
            do {
                modelContainer = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Failed to create ModelContainer after reset: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { startCronScheduler() }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    cronScheduler?.rescheduleAll()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    cronScheduler?.scheduleBackgroundTask()
                }
        }
        .modelContainer(modelContainer)
    }

    private func startCronScheduler() {
        guard cronScheduler == nil else { return }
        let scheduler = CronScheduler(modelContainer: modelContainer)
        scheduler.start()
        cronScheduler = scheduler

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: CronScheduler.bgTaskIdentifier,
            using: nil
        ) { task in
            scheduler.handleBackgroundTask(task as! BGAppRefreshTask)
        }
    }

    // MARK: - Deep Link Handling

    /// Handles URL scheme: iclaw://cron/trigger/{jobId} and iclaw://cron/run-due
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "iclaw" else { return }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let host = url.host ?? ""

        // Normalize: iclaw://cron/trigger/{id} or iclaw://cron/run-due
        let fullPath = ([host] + pathComponents).joined(separator: "/")

        if fullPath.hasPrefix("cron/trigger/") {
            let jobIdStr = fullPath.replacingOccurrences(of: "cron/trigger/", with: "")
            if let jobId = UUID(uuidString: jobIdStr) {
                triggerCronJob(id: jobId)
            }
        } else if fullPath == "cron/run-due" {
            triggerAllDueJobs()
        }
    }

    private func triggerCronJob(id: UUID) {
        Task { @MainActor in
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<CronJob>(
                predicate: #Predicate { $0.id == id }
            )
            guard let job = try? context.fetch(descriptor).first,
                  let agent = job.agent,
                  job.isEnabled else { return }

            let executor = CronExecutor(modelContainer: modelContainer)
            await executor.executeJob(job, agent: agent, context: context)
        }
    }

    private func triggerAllDueJobs() {
        Task { @MainActor in
            let context = ModelContext(modelContainer)
            let dueJobs = CronScheduler.fetchDueJobs(context: context, now: Date())

            let executor = CronExecutor(modelContainer: modelContainer)
            for job in dueJobs {
                guard let agent = job.agent else { continue }
                await executor.executeJob(job, agent: agent, context: context)
            }
        }
    }
}
