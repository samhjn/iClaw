import Foundation
import SwiftData

struct CronTools {
    let agent: Agent
    let modelContext: ModelContext

    func scheduleCron(arguments: [String: Any]) -> String {
        guard let name = arguments["name"] as? String else {
            return "[Error] Missing required parameter: name"
        }
        guard let expression = arguments["cron_expression"] as? String else {
            return "[Error] Missing required parameter: cron_expression"
        }
        guard let hint = arguments["job_hint"] as? String else {
            return "[Error] Missing required parameter: job_hint"
        }

        if let validationError = CronParser.validate(expression) {
            return "[Error] Invalid cron expression: \(validationError)"
        }

        let enabled = arguments["enabled"] as? Bool ?? true

        let job = CronJob(
            name: name,
            cronExpression: expression,
            jobHint: hint,
            agent: agent,
            isEnabled: enabled
        )

        if let next = try? CronParser.nextFireDate(after: Date(), for: expression) {
            job.nextRunAt = next
        }

        modelContext.insert(job)
        try? modelContext.save()

        let description = CronParser.describe(expression)
        let nextStr = job.nextRunAt.map { formatDate($0) } ?? "unknown"

        return """
        Cron job created successfully.
        - Name: \(name)
        - ID: \(job.id.uuidString)
        - Schedule: \(expression) (\(description))
        - Next run: \(nextStr)
        - Enabled: \(enabled)

        The job will automatically create a new session and run your hint as a trigger message at each scheduled time.
        """
    }

    func unscheduleCron(arguments: [String: Any]) -> String {
        guard let jobIdStr = arguments["job_id"] as? String,
              let jobId = UUID(uuidString: jobIdStr) else {
            return "[Error] Missing or invalid job_id parameter"
        }

        let deleteCompletely = arguments["delete"] as? Bool ?? false

        guard let job = agent.cronJobs.first(where: { $0.id == jobId }) else {
            let available = agent.cronJobs.map { "  - \($0.name): \($0.id.uuidString)" }.joined(separator: "\n")
            return "[Error] Job not found. Available jobs:\n\(available.isEmpty ? "  (none)" : available)"
        }

        if deleteCompletely {
            let name = job.name
            modelContext.delete(job)
            try? modelContext.save()
            return "Cron job '\(name)' has been permanently deleted."
        } else {
            job.isEnabled = false
            job.updatedAt = Date()
            try? modelContext.save()
            return "Cron job '\(job.name)' has been disabled. Use schedule_cron to create a new one or re-enable via UI."
        }
    }

    func listCron() -> String {
        let jobs = agent.cronJobs
        if jobs.isEmpty {
            return "(No cron jobs configured for this agent)"
        }

        return jobs.map { job in
            let status = job.isEnabled ? "enabled" : "disabled"
            let nextStr = job.nextRunAt.map { formatDate($0) } ?? "not scheduled"
            let lastStr = job.lastRunAt.map { formatDate($0) } ?? "never"
            let description = CronParser.describe(job.cronExpression)

            return """
            - **\(job.name)** [\(status)]
              ID: \(job.id.uuidString)
              Schedule: \(job.cronExpression) (\(description))
              Next: \(nextStr) | Last: \(lastStr) | Runs: \(job.runCount)
              Hint: \(job.jobHint.prefix(100))\(job.jobHint.count > 100 ? "..." : "")
            """
        }.joined(separator: "\n\n")
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }
}
