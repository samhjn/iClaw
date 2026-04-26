import Foundation
import SwiftData
import UserNotifications

/// Executes a cron job: creates a new session, injects the job hint, and runs the LLM agent loop.
@MainActor
final class CronExecutor {
    private let modelContainer: ModelContainer
    /// Optional keep-alive manager; set by the scheduler to receive session lifecycle events.
    var keepAliveManager: BackgroundKeepAliveManager?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func executeJob(_ job: CronJob, agent: Agent, context: ModelContext) async {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        // Persist the session→agent association in its own transaction *before*
        // any other mutations. Bundling insert+agent+isActive+messages into a
        // single later save (via `claimNextRun`) was racy: if anything in that
        // larger transaction failed, the session could land in the store
        // without its agent reference, and downstream UI/RAG code would treat
        // it as orphaned ("cron-created session has no agent"). Mirrors the
        // pattern used in `SessionService.createSession` and
        // `SubAgentManager.createSubAgent`.
        let sessionTitle = "⏰ \(job.name) — \(formatter.string(from: Date()))"
        let session = Session(title: sessionTitle)
        context.insert(session)
        session.agent = agent
        try? context.save()

        session.isActive = true

        let triggerMessage = buildTriggerMessage(job: job)
        let userMsg = Message(role: .user, content: triggerMessage)
        context.insert(userMsg)
        session.messages.append(userMsg)

        // Claim this run before any agent work happens — see `claimNextRun`.
        claimNextRun(for: job, context: context)

        keepAliveManager?.onSessionStarted(sessionId: session.id, sessionName: sessionTitle)

        var hadError = false
        defer {
            session.isActive = false
            try? context.save()
            keepAliveManager?.onSessionCompleted(sessionId: session.id, sessionName: sessionTitle, isError: hadError)
        }

        let router = ModelRouter(modelContext: context)
        guard router.primaryProvider(for: agent) != nil else {
            let errorMsg = Message(
                role: .assistant,
                content: L10n.CronExec.noProvider
            )
            context.insert(errorMsg)
            session.messages.append(errorMsg)
            hadError = true
            finalizeJob(job, session: session, context: context)
            return
        }

        hadError = await runAgentLoop(
            session: session,
            agent: agent,
            router: router,
            context: context
        )

        finalizeJob(job, session: session, context: context)

        await sendLocalNotification(jobName: job.name, sessionTitle: sessionTitle)
    }

    // MARK: - Agent execution loop (non-streaming, headless)

    /// Returns `true` if the loop ended due to an error.
    private func runAgentLoop(
        session: Session,
        agent: Agent,
        router: ModelRouter,
        context: ModelContext,
        maxRounds: Int = 10
    ) async -> Bool {
        let promptBuilder = PromptBuilder()
        let contextManager = ContextManager()
        let fnRouter = FunctionCallRouter(agent: agent, modelContext: context, sessionId: session.id)
        let caps = router.primaryModelCapabilities(for: agent)

        for _ in 0..<maxRounds {
            let systemPrompt = promptBuilder.buildSystemPrompt(for: agent, isSubAgent: agent.parentAgent != nil)
            var messages = contextManager.buildContextWindow(session: session, systemPrompt: systemPrompt)
            ChatViewModel.stripUnsupportedModalities(from: &messages, capabilities: caps)

            do {
                let (response, _) = try await router.chatCompletionWithFailover(
                    agent: agent,
                    messages: messages,
                    tools: ToolDefinitions.tools(for: agent)
                )

                guard let choice = response.choices.first, let msg = choice.message else { break }

                if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                    let assistantMsg = Message(
                        role: .assistant,
                        content: msg.content,
                        toolCallsData: try? JSONEncoder().encode(toolCalls)
                    )
                    context.insert(assistantMsg)
                    session.messages.append(assistantMsg)

                    for tc in toolCalls {
                        let result = await fnRouter.execute(toolCall: tc)
                        let toolMsg = Message(
                            role: .tool,
                            content: result.text,
                            toolCallId: tc.id,
                            name: tc.function.name
                        )
                        if let images = result.imageAttachments,
                           let data = try? JSONEncoder().encode(images) {
                            toolMsg.imageAttachmentsData = data
                            toolMsg.recalculateTokenEstimate()
                        }
                        context.insert(toolMsg)
                        session.messages.append(toolMsg)
                    }
                    try? context.save()
                    continue
                }

                if let content = msg.content, !content.isEmpty {
                    let assistantMsg = Message(role: .assistant, content: content)
                    context.insert(assistantMsg)
                    session.messages.append(assistantMsg)
                    try? context.save()
                }

                break
            } catch {
                let errorMsg = Message(
                    role: .assistant,
                    content: "[CronJob Error] \(error.localizedDescription)"
                )
                context.insert(errorMsg)
                session.messages.append(errorMsg)
                try? context.save()
                return true
            }
        }
        return false
    }

    // MARK: - Helpers

    private func buildTriggerMessage(job: CronJob) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        return """
        [Automated CronJob Trigger]
        Job: \(job.name)
        Schedule: \(job.cronExpression) (\(CronParser.describe(job.cronExpression)))
        Triggered at: \(formatter.string(from: Date()))
        Run #\(job.runCount + 1)

        ---

        \(job.jobHint)
        """
    }

    /// Advances `job.nextRunAt` to the next scheduled fire after now and
    /// commits, making the job invisible to `fetchDueJobs` for the rest of the
    /// current period. Called at the start of `executeJob` to prevent any
    /// concurrent trigger path (foreground `CronScheduler` resuming
    /// mid-flight, `BGAppRefreshTask`, a second App Intent invocation) from
    /// double-executing the same job while `runAgentLoop` is awaiting the
    /// network. Standard cron semantics: a failed run is not auto-retried;
    /// the next scheduled fire takes over.
    func claimNextRun(for job: CronJob, context: ModelContext) {
        if let next = try? CronParser.nextFireDate(after: Date(), for: job.cronExpression) {
            job.nextRunAt = next
        }
        try? context.save()
    }

    private func finalizeJob(_ job: CronJob, session: Session, context: ModelContext) {
        job.lastRunAt = Date()
        job.runCount += 1
        job.lastSessionId = session.id
        job.updatedAt = Date()

        // Re-advance based on completion time. `executeJob` already advanced
        // nextRunAt at the start to prevent concurrent re-trigger; this second
        // pass is the authoritative schedule for the next fire and is always
        // >= the start-time claim, so it never moves nextRunAt backwards.
        if let next = try? CronParser.nextFireDate(after: Date(), for: job.cronExpression) {
            job.nextRunAt = next
        }

        session.updatedAt = Date()
        try? context.save()
    }

    @MainActor
    private func sendLocalNotification(jobName: String, sessionTitle: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

        let content = UNMutableNotificationContent()
        content.title = L10n.CronExec.completed
        content.body = L10n.CronExec.completedBody(jobName)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
