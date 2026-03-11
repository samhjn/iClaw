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
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { startCronScheduler() }
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
}
