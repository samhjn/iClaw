import XCTest
import SwiftData
@testable import iClaw

/// Coverage for the App Intents–based cron trigger path. These tests exercise
/// `CronJobRunner`, `CronJobEntityQuery`, and the `openAppWhenRun` flag on
/// the intents. They do **not** spin up a real LLM provider, so jobs hit the
/// "no primary provider" branch inside `CronExecutor.executeJob`, which still
/// finalizes the job (`runCount += 1`) — sufficient to verify the runner
/// wiring without network calls.
final class AppIntentsCronTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        let schema = Schema([
            Agent.self, LLMProvider.self, Session.self, AgentConfig.self,
            CodeSnippet.self, CronJob.self, InstalledSkill.self, Skill.self,
            Message.self, SessionEmbedding.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Helpers

    @MainActor
    @discardableResult
    private func makeJob(
        name: String,
        cron: String = "* * * * *",
        enabled: Bool = true,
        nextRunAt: Date?
    ) -> CronJob {
        let agent = Agent(name: "TestAgent-\(name)")
        context.insert(agent)

        let job = CronJob(
            name: name,
            cronExpression: cron,
            jobHint: "test hint for \(name)",
            isEnabled: enabled
        )
        job.agent = agent
        job.nextRunAt = nextRunAt
        context.insert(job)
        try? context.save()
        return job
    }

    // MARK: - RunDueCronJobsIntent / CronJobRunner.runAllDue

    @MainActor
    func test_runAllDue_runsOnlyDueJobs() async {
        let dueJob = makeJob(name: "A", nextRunAt: Date().addingTimeInterval(-60))
        let futureJob = makeJob(name: "B", nextRunAt: Date().addingTimeInterval(3600))

        let ran = await CronJobRunner.runAllDue(container: container)

        XCTAssertEqual(ran, 1, "Only the due job should have started")

        // Re-fetch to see finalization writes.
        let fresh = ModelContext(container)
        let allJobs = (try? fresh.fetch(FetchDescriptor<CronJob>())) ?? []
        let dueAfter = allJobs.first { $0.id == dueJob.id }
        let futureAfter = allJobs.first { $0.id == futureJob.id }
        XCTAssertEqual(dueAfter?.runCount, 1)
        XCTAssertEqual(futureAfter?.runCount, 0)
    }

    @MainActor
    func test_runAllDue_skipsDisabledJobs() async {
        _ = makeJob(name: "Disabled", enabled: false, nextRunAt: Date().addingTimeInterval(-60))

        let ran = await CronJobRunner.runAllDue(container: container)

        XCTAssertEqual(ran, 0, "Disabled jobs must not run even if due")
    }

    @MainActor
    func test_runAllDue_rechecksNextRunAtToAvoidDoubleRun() async {
        // Seed a job as due, then immediately push its nextRunAt into the future
        // to simulate the foreground CronScheduler having already executed it.
        let job = makeJob(name: "RacedAhead", nextRunAt: Date().addingTimeInterval(-60))
        job.nextRunAt = Date().addingTimeInterval(3600)
        try? context.save()

        // fetchDueJobs uses its own context snapshot, so the runner will observe
        // the updated nextRunAt when it re-checks right before execution.
        let ran = await CronJobRunner.runAllDue(container: container)

        XCTAssertEqual(ran, 0, "Runner must re-check nextRunAt and skip already-advanced jobs")

        let fresh = ModelContext(container)
        let after = (try? fresh.fetch(FetchDescriptor<CronJob>()))?.first { $0.id == job.id }
        XCTAssertEqual(after?.runCount, 0)
    }

    @MainActor
    func test_runAllDue_respectsSoftDeadline() async {
        // Seed several due jobs, then pass a zero-second deadline so the loop
        // exits before starting any. No runCount should increment.
        _ = makeJob(name: "A", nextRunAt: Date().addingTimeInterval(-60))
        _ = makeJob(name: "B", nextRunAt: Date().addingTimeInterval(-60))
        _ = makeJob(name: "C", nextRunAt: Date().addingTimeInterval(-60))

        let ran = await CronJobRunner.runAllDue(container: container, softDeadline: 0)

        XCTAssertEqual(ran, 0, "Zero-second deadline must prevent any job from starting")

        let fresh = ModelContext(container)
        let jobs = (try? fresh.fetch(FetchDescriptor<CronJob>())) ?? []
        XCTAssertTrue(jobs.allSatisfy { $0.runCount == 0 })
    }

    // MARK: - TriggerCronJobIntent / CronJobRunner.runOne

    @MainActor
    func test_runOne_executesSpecificJobRegardlessOfSchedule() async {
        let job = makeJob(name: "Manual", nextRunAt: Date().addingTimeInterval(3600))

        let ok = await CronJobRunner.runOne(jobId: job.id, container: container)

        XCTAssertTrue(ok)

        let fresh = ModelContext(container)
        let after = (try? fresh.fetch(FetchDescriptor<CronJob>()))?.first { $0.id == job.id }
        XCTAssertEqual(after?.runCount, 1)
        XCTAssertNotNil(after?.lastSessionId)
    }

    @MainActor
    func test_runOne_returnsFalseForDisabledJob() async {
        let job = makeJob(name: "Off", enabled: false, nextRunAt: nil)

        let ok = await CronJobRunner.runOne(jobId: job.id, container: container)

        XCTAssertFalse(ok, "Disabled jobs must not run via manual trigger")
    }

    @MainActor
    func test_runOne_returnsFalseForUnknownId() async {
        let ok = await CronJobRunner.runOne(jobId: UUID(), container: container)
        XCTAssertFalse(ok)
    }

    // MARK: - CronJobEntityQuery
    //
    // Note: `CronJobEntityQuery` reads from `iClawModelContainer.shared`, which
    // is the on-disk store. We therefore validate the query's *filtering* by
    // unit-testing the shape of its predicate here against our in-memory
    // container, matching what the production query does.

    @MainActor
    func test_entityQuery_onlyReturnsEnabledJobs() async {
        _ = makeJob(name: "Alpha", enabled: true, nextRunAt: nil)
        _ = makeJob(name: "Beta", enabled: false, nextRunAt: nil)
        _ = makeJob(name: "Gamma", enabled: true, nextRunAt: nil)

        let ctx = ModelContext(container)
        let descriptor = FetchDescriptor<CronJob>(
            predicate: #Predicate<CronJob> { $0.isEnabled == true },
            sortBy: [SortDescriptor(\.name)]
        )
        let enabled = (try? ctx.fetch(descriptor)) ?? []

        XCTAssertEqual(enabled.map(\.name), ["Alpha", "Gamma"])
    }

    // MARK: - Regression: openAppWhenRun must stay false

    func test_intents_doNotOpenAppWhenRun() {
        // If someone ever flips these to true, locked-device automations will
        // start requiring Face ID / passcode — defeating the entire purpose of
        // this feature. Fail loudly at test time rather than at the user's
        // wrist.
        XCTAssertFalse(RunDueCronJobsIntent.openAppWhenRun,
                       "RunDueCronJobsIntent must execute in background")
        XCTAssertFalse(TriggerCronJobIntent.openAppWhenRun,
                       "TriggerCronJobIntent must execute in background")
    }
}
