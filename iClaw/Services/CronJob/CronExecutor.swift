import Foundation
import SwiftData
import UserNotifications

/// Executes a cron job: creates a new session, injects the job hint, and runs the LLM agent loop.
final class CronExecutor {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func executeJob(_ job: CronJob, agent: Agent, context: ModelContext) async {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let sessionTitle = "⏰ \(job.name) — \(formatter.string(from: Date()))"
        let session = Session(title: sessionTitle, agent: agent)
        context.insert(session)

        let triggerMessage = buildTriggerMessage(job: job)
        let userMsg = Message(role: .user, content: triggerMessage, session: session)
        context.insert(userMsg)
        session.messages.append(userMsg)
        try? context.save()

        let router = ModelRouter(modelContext: context)
        guard router.primaryProvider(for: agent) != nil else {
            let errorMsg = Message(
                role: .assistant,
                content: "[CronJob Error] No LLM provider configured.",
                session: session
            )
            context.insert(errorMsg)
            session.messages.append(errorMsg)
            finalizeJob(job, session: session, context: context)
            return
        }

        await runAgentLoop(
            session: session,
            agent: agent,
            router: router,
            context: context
        )

        finalizeJob(job, session: session, context: context)

        await sendLocalNotification(jobName: job.name, sessionTitle: sessionTitle)
    }

    // MARK: - Agent execution loop (non-streaming, headless)

    private func runAgentLoop(
        session: Session,
        agent: Agent,
        router: ModelRouter,
        context: ModelContext,
        maxRounds: Int = 10
    ) async {
        let promptBuilder = PromptBuilder()
        let contextManager = ContextManager()
        let fnRouter = FunctionCallRouter(agent: agent, modelContext: context)

        for _ in 0..<maxRounds {
            let systemPrompt = promptBuilder.buildSystemPrompt(for: agent, isSubAgent: agent.parentAgent != nil)
            let messages = contextManager.buildContextWindow(session: session, systemPrompt: systemPrompt)

            do {
                let (response, _) = try await router.chatCompletionWithFailover(
                    agent: agent,
                    messages: messages,
                    tools: ToolDefinitions.allTools
                )

                guard let choice = response.choices.first, let msg = choice.message else { break }

                if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                    let assistantMsg = Message(
                        role: .assistant,
                        content: msg.content,
                        toolCallsData: try? JSONEncoder().encode(toolCalls),
                        session: session
                    )
                    context.insert(assistantMsg)
                    session.messages.append(assistantMsg)

                    for tc in toolCalls {
                        let result = await fnRouter.execute(toolCall: tc)
                        let toolMsg = Message(
                            role: .tool,
                            content: result,
                            toolCallId: tc.id,
                            name: tc.function.name,
                            session: session
                        )
                        context.insert(toolMsg)
                        session.messages.append(toolMsg)
                    }
                    try? context.save()
                    continue
                }

                if let content = msg.content, !content.isEmpty {
                    let assistantMsg = Message(role: .assistant, content: content, session: session)
                    context.insert(assistantMsg)
                    session.messages.append(assistantMsg)
                    try? context.save()
                }

                break
            } catch {
                let errorMsg = Message(
                    role: .assistant,
                    content: "[CronJob Error] \(error.localizedDescription)",
                    session: session
                )
                context.insert(errorMsg)
                session.messages.append(errorMsg)
                try? context.save()
                break
            }
        }
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

    private func finalizeJob(_ job: CronJob, session: Session, context: ModelContext) {
        job.lastRunAt = Date()
        job.runCount += 1
        job.lastSessionId = session.id
        job.updatedAt = Date()

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
        content.title = "CronJob Completed"
        content.body = "\(jobName) finished. Tap to view the session."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
