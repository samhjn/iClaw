import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct iClawApp: App {
    let modelContainer: ModelContainer
    @State private var cronScheduler: CronScheduler?
    @State private var launchTaskManager: LaunchTaskManager
    private let bgTaskCoordinator: CronBGTaskCoordinator

    init() {
        Self.installExceptionHandler()

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
            SessionEmbedding.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
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

        _launchTaskManager = State(initialValue: LaunchTaskManager(container: modelContainer))

        Self.resetStaleActiveSessions(in: modelContainer)

        let coordinator = CronBGTaskCoordinator()
        coordinator.registerCronTask()
        bgTaskCoordinator = coordinator
    }

    private static func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let info = """
            [iClawApp] Uncaught NSException: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "unknown")
            User Info: \(exception.userInfo ?? [:])
            Stack:
            \(exception.callStackSymbols.joined(separator: "\n"))
            """
            print(info)
        }
    }

    /// Sessions stuck in `isActive` from a previous crash or force-quit can never
    /// have a live agent loop. Reset them so they don't block new interactions.
    private static func resetStaleActiveSessions(in container: ModelContainer) {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate<Session> { $0.isActive == true }
        )
        guard let stale = try? context.fetch(descriptor), !stale.isEmpty else { return }
        for session in stale {
            session.isActive = false
        }
        try? context.save()
        print("[iClawApp] Reset \(stale.count) stale active session(s).")
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .launchTaskOverlay(manager: launchTaskManager)
                .onAppear {
                    launchTaskManager.runAll()
                    startCronScheduler()
                }
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
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                cronScheduler?.pause()
            case .active:
                cronScheduler?.resume()
            default:
                break
            }
        }
    }

    private func startCronScheduler() {
        guard cronScheduler == nil else { return }
        let scheduler = CronScheduler(modelContainer: modelContainer)
        scheduler.start()
        cronScheduler = scheduler
        bgTaskCoordinator.scheduler = scheduler
    }

    // MARK: - Deep Link Handling

    /// Handles URL scheme: iclaw://cron/trigger/{jobId} and iclaw://cron/run-due
    private func handleDeepLink(_ url: URL) {
        if url.scheme == "agentfile" {
            handleAgentFileLink(url)
            return
        }

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

    private func handleAgentFileLink(_ url: URL) {
        let ref = url.absoluteString
        guard let (agentId, filename) = AgentFileManager.parseFileReference(ref) else { return }
        let ext = (filename as NSString).pathExtension.lowercased()
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif"]

        if imageExts.contains(ext) {
            if let data = AgentFileManager.shared.loadImageData(from: ref),
               let image = UIImage(data: data) {
                ImagePreviewCoordinator.shared.show(image)
            }
        } else {
            let fileURL = AgentFileManager.shared.fileURL(agentId: agentId, name: filename)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
        }
    }

    private func triggerCronJob(id: UUID) {
        Task { @MainActor in
            await cronScheduler?.runManualJob(jobId: id)
        }
    }

    private func triggerAllDueJobs() {
        Task { @MainActor in
            await cronScheduler?.runDueJobsNow()
        }
    }
}
