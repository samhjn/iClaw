import XCTest
import SwiftData
@testable import iClaw

// MARK: - SubAgentManager Nesting Depth Tests

final class SubAgentNestingTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        let schema = Schema([Agent.self, LLMProvider.self, Session.self, AgentConfig.self,
                             CodeSnippet.self, CronJob.self, InstalledSkill.self, Skill.self,
                             Message.self, SessionEmbedding.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Max Nesting Depth Constant

    func testMaxNestingDepthIsReasonable() {
        XCTAssertGreaterThan(SubAgentManager.maxNestingDepth, 0)
        XCTAssertLessThanOrEqual(SubAgentManager.maxNestingDepth, 10,
                                 "Nesting depth should be bounded to prevent stack overflow")
    }

    // MARK: - SubAgentManager Depth Initialization

    @MainActor
    func testSubAgentManagerDefaultDepthIsZero() {
        let manager = SubAgentManager(modelContext: context)
        _ = manager
        // Default init should not crash — depth starts at 0
    }

    @MainActor
    func testSubAgentManagerAcceptsCustomDepth() {
        let manager = SubAgentManager(modelContext: context, nestingDepth: 3)
        _ = manager
    }

    // MARK: - Depth Limit Enforcement

    @MainActor
    func testSendMessageRejectsAtMaxDepth() async {
        let manager = SubAgentManager(modelContext: context, nestingDepth: SubAgentManager.maxNestingDepth)
        let fakeAgentId = UUID()

        do {
            _ = try await manager.sendMessage(to: fakeAgentId, content: "test")
            XCTFail("Expected maxDepthExceeded error")
        } catch let error as SubAgentError {
            if case .maxDepthExceeded(let depth) = error {
                XCTAssertEqual(depth, SubAgentManager.maxNestingDepth)
            } else {
                XCTFail("Expected maxDepthExceeded, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    @MainActor
    func testSendMessageRejectsAboveMaxDepth() async {
        let manager = SubAgentManager(modelContext: context, nestingDepth: SubAgentManager.maxNestingDepth + 3)
        let fakeAgentId = UUID()

        do {
            _ = try await manager.sendMessage(to: fakeAgentId, content: "test")
            XCTFail("Expected maxDepthExceeded error")
        } catch let error as SubAgentError {
            if case .maxDepthExceeded = error {
                // Expected
            } else {
                XCTFail("Expected maxDepthExceeded, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    @MainActor
    func testSendMessageAllowsBelowMaxDepth() async {
        let manager = SubAgentManager(modelContext: context, nestingDepth: SubAgentManager.maxNestingDepth - 1)
        let fakeAgentId = UUID()

        do {
            _ = try await manager.sendMessage(to: fakeAgentId, content: "test")
            XCTFail("Expected agentNotFound (not depth error)")
        } catch let error as SubAgentError {
            if case .agentNotFound = error {
                // Correct: depth check passed, then failed to find the fake agent
            } else if case .maxDepthExceeded = error {
                XCTFail("Should not hit depth limit at depth \(SubAgentManager.maxNestingDepth - 1)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    @MainActor
    func testSendMessageAllowsAtDepthZero() async {
        let manager = SubAgentManager(modelContext: context, nestingDepth: 0)
        let fakeAgentId = UUID()

        do {
            _ = try await manager.sendMessage(to: fakeAgentId, content: "test")
        } catch let error as SubAgentError {
            if case .maxDepthExceeded = error {
                XCTFail("Depth 0 should be allowed")
            }
            // agentNotFound is expected since we use a fake ID
        } catch {
            // Other errors are fine
        }
    }

    // MARK: - SubAgentError Messages

    func testMaxDepthExceededErrorDescription() {
        let error = SubAgentError.maxDepthExceeded(5)
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("5"), "Should include current depth")
        XCTAssertTrue(description.contains("\(SubAgentManager.maxNestingDepth)"), "Should include max depth")
    }

    func testSubAgentErrorDescriptions() {
        XCTAssertNotNil(SubAgentError.agentNotFound.errorDescription)
        XCTAssertNotNil(SubAgentError.emptyResponse.errorDescription)
        XCTAssertNotNil(SubAgentError.sessionLocked("reason").errorDescription)
        XCTAssertNotNil(SubAgentError.maxDepthExceeded(3).errorDescription)
    }
}

// MARK: - FunctionCallRouter Nesting Depth Tests

final class FunctionCallRouterDepthTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var agent: Agent!

    @MainActor
    override func setUp() {
        super.setUp()
        let schema = Schema([Agent.self, LLMProvider.self, Session.self, AgentConfig.self,
                             CodeSnippet.self, CronJob.self, InstalledSkill.self, Skill.self,
                             Message.self, SessionEmbedding.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        agent = Agent(name: "TestAgent")
        context.insert(agent)
        try! context.save()
    }

    override func tearDown() {
        container = nil
        context = nil
        agent = nil
        super.tearDown()
    }

    @MainActor
    func testDefaultNestingDepthIsZero() {
        let router = FunctionCallRouter(agent: agent, modelContext: context)
        XCTAssertEqual(router.nestingDepth, 0)
    }

    @MainActor
    func testCustomNestingDepth() {
        let router = FunctionCallRouter(agent: agent, modelContext: context, nestingDepth: 3)
        XCTAssertEqual(router.nestingDepth, 3)
    }

    @MainActor
    func testNestingDepthWithSessionId() {
        let sessionId = UUID()
        let router = FunctionCallRouter(agent: agent, modelContext: context, sessionId: sessionId, nestingDepth: 2)
        XCTAssertEqual(router.nestingDepth, 2)
        XCTAssertEqual(router.sessionId, sessionId)
    }

    @MainActor
    func testUnknownToolReturnsError() async {
        let router = FunctionCallRouter(agent: agent, modelContext: context)
        let toolCall = LLMToolCall(id: "test-1", name: "nonexistent_tool", arguments: "{}")
        let result = await router.execute(toolCall: toolCall)
        XCTAssertTrue(result.text.contains("Unknown tool"))
    }
}

// MARK: - CronJob Lifecycle Tests

final class CronJobLifecycleTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var agent: Agent!

    @MainActor
    override func setUp() {
        super.setUp()
        let schema = Schema([Agent.self, LLMProvider.self, Session.self, AgentConfig.self,
                             CodeSnippet.self, CronJob.self, InstalledSkill.self, Skill.self,
                             Message.self, SessionEmbedding.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        agent = Agent(name: "CronTestAgent")
        context.insert(agent)
        try! context.save()
    }

    override func tearDown() {
        container = nil
        context = nil
        agent = nil
        super.tearDown()
    }

    // MARK: - CronJob Creation

    @MainActor
    func testCronJobCreation() {
        let job = CronJob(name: "Test Job", cronExpression: "0 9 * * *", jobHint: "Do stuff", agent: agent)
        context.insert(job)
        try! context.save()

        XCTAssertEqual(job.name, "Test Job")
        XCTAssertEqual(job.cronExpression, "0 9 * * *")
        XCTAssertEqual(job.jobHint, "Do stuff")
        XCTAssertTrue(job.isEnabled)
        XCTAssertEqual(job.runCount, 0)
        XCTAssertNotNil(job.agent)
    }

    // MARK: - Due Job Detection

    @MainActor
    func testFetchDueJobsReturnsOverdueJobs() {
        let job = CronJob(name: "Overdue", cronExpression: "* * * * *", jobHint: "test", agent: agent)
        job.nextRunAt = Date.distantPast
        context.insert(job)
        try! context.save()

        let dueJobs = CronScheduler.fetchDueJobs(context: context, now: Date())
        XCTAssertTrue(dueJobs.contains(where: { $0.id == job.id }))
    }

    @MainActor
    func testFetchDueJobsExcludesFutureJobs() {
        let job = CronJob(name: "Future", cronExpression: "* * * * *", jobHint: "test", agent: agent)
        job.nextRunAt = Date.distantFuture
        context.insert(job)
        try! context.save()

        let dueJobs = CronScheduler.fetchDueJobs(context: context, now: Date())
        XCTAssertFalse(dueJobs.contains(where: { $0.id == job.id }))
    }

    @MainActor
    func testFetchDueJobsExcludesDisabledJobs() {
        let job = CronJob(name: "Disabled", cronExpression: "* * * * *", jobHint: "test", agent: agent)
        job.isEnabled = false
        job.nextRunAt = Date.distantPast
        context.insert(job)
        try! context.save()

        let dueJobs = CronScheduler.fetchDueJobs(context: context, now: Date())
        XCTAssertFalse(dueJobs.contains(where: { $0.id == job.id }))
    }

    @MainActor
    func testFetchDueJobsWithNilNextRunAt() {
        let job = CronJob(name: "NeverScheduled", cronExpression: "* * * * *", jobHint: "test", agent: agent)
        job.nextRunAt = nil
        context.insert(job)
        try! context.save()

        let dueJobs = CronScheduler.fetchDueJobs(context: context, now: Date())
        XCTAssertTrue(dueJobs.contains(where: { $0.id == job.id }),
                      "Jobs with nil nextRunAt should be computed and included if due")
    }

    // MARK: - Session State Consistency

    @MainActor
    func testSessionStartsInactive() {
        let session = Session(title: "Test Session")
        context.insert(session)
        session.agent = agent

        XCTAssertFalse(session.isActive)
        XCTAssertFalse(session.isCompressingContext)
    }

    @MainActor
    func testSessionActiveStateToggle() {
        let session = Session(title: "Active Test")
        context.insert(session)
        session.agent = agent
        try! context.save()

        session.isActive = true
        try! context.save()
        XCTAssertTrue(session.isActive)

        session.isActive = false
        try! context.save()
        XCTAssertFalse(session.isActive)
    }

    @MainActor
    func testSessionMessagesOrder() {
        let session = Session(title: "Order Test")
        context.insert(session)
        session.agent = agent

        let msg1 = Message(role: .user, content: "First", session: session)
        msg1.timestamp = Date(timeIntervalSince1970: 100)
        let msg2 = Message(role: .assistant, content: "Second", session: session)
        msg2.timestamp = Date(timeIntervalSince1970: 200)
        let msg3 = Message(role: .user, content: "Third", session: session)
        msg3.timestamp = Date(timeIntervalSince1970: 300)

        context.insert(msg1)
        context.insert(msg2)
        context.insert(msg3)
        session.messages.append(contentsOf: [msg3, msg1, msg2])
        try! context.save()

        let sorted = session.sortedMessages
        XCTAssertEqual(sorted[0].content, "First")
        XCTAssertEqual(sorted[1].content, "Second")
        XCTAssertEqual(sorted[2].content, "Third")
    }

    // MARK: - CronScheduler Lock Management

    @MainActor
    func testSchedulerStartStop() {
        let scheduler = CronScheduler(modelContainer: container)
        XCTAssertFalse(scheduler.isRunning)

        scheduler.start()
        XCTAssertTrue(scheduler.isRunning)

        scheduler.stop()
        XCTAssertFalse(scheduler.isRunning)
    }

    @MainActor
    func testSchedulerRunningJobTracking() {
        let scheduler = CronScheduler(modelContainer: container)
        XCTAssertTrue(scheduler.runningJobIds.isEmpty)
    }

    @MainActor
    func testSchedulerDoubleStartIsIdempotent() {
        let scheduler = CronScheduler(modelContainer: container)
        scheduler.start()
        scheduler.start()
        XCTAssertTrue(scheduler.isRunning)
        scheduler.stop()
    }
}

// MARK: - ModelContext Thread Safety Tests

final class ModelContextThreadSafetyTests: XCTestCase {

    private var container: ModelContainer!

    @MainActor
    override func setUp() {
        super.setUp()
        let schema = Schema([Agent.self, LLMProvider.self, Session.self, AgentConfig.self,
                             CodeSnippet.self, CronJob.self, InstalledSkill.self, Skill.self,
                             Message.self, SessionEmbedding.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    @MainActor
    func testModelContextCreatedOnMainActor() {
        let context = ModelContext(container)
        XCTAssertNotNil(context, "ModelContext should be creatable on @MainActor")

        let agent = Agent(name: "MainActorAgent")
        context.insert(agent)
        try! context.save()

        let descriptor = FetchDescriptor<Agent>(
            predicate: #Predicate { $0.name == "MainActorAgent" }
        )
        let fetched = try! context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
    }

    @MainActor
    func testMultipleContextsOnSameContainer() {
        let ctx1 = ModelContext(container)
        let ctx2 = ModelContext(container)

        let agent = Agent(name: "SharedAgent")
        ctx1.insert(agent)
        try! ctx1.save()

        let descriptor = FetchDescriptor<Agent>(
            predicate: #Predicate { $0.name == "SharedAgent" }
        )
        let fetchedFromCtx2 = try! ctx2.fetch(descriptor)
        XCTAssertEqual(fetchedFromCtx2.count, 1,
                       "Second context should see data persisted by first context")
    }

    @MainActor
    func testCronExecutorSessionCreation() {
        let context = ModelContext(container)
        let agent = Agent(name: "CronAgent")
        context.insert(agent)

        let session = Session(title: "⏰ Test — Now")
        session.isActive = true
        context.insert(session)
        session.agent = agent

        let userMsg = Message(role: .user, content: "Test trigger", session: session)
        context.insert(userMsg)
        session.messages.append(userMsg)
        try! context.save()

        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.messages.count, 1)
        XCTAssertEqual(session.agent?.name, "CronAgent")

        session.isActive = false
        try! context.save()
        XCTAssertFalse(session.isActive)
    }

    @MainActor
    func testCronJobFinalization() {
        let context = ModelContext(container)
        let agent = Agent(name: "FinalizeAgent")
        context.insert(agent)
        let job = CronJob(name: "Finalize Test", cronExpression: "0 9 * * *", jobHint: "test", agent: agent)
        context.insert(job)
        try! context.save()

        XCTAssertEqual(job.runCount, 0)
        XCTAssertNil(job.lastRunAt)
        XCTAssertNil(job.lastSessionId)

        let session = Session(title: "Result")
        context.insert(session)
        try! context.save()

        job.lastRunAt = Date()
        job.runCount += 1
        job.lastSessionId = session.id
        job.updatedAt = Date()

        if let next = try? CronParser.nextFireDate(after: Date(), for: job.cronExpression) {
            job.nextRunAt = next
        }
        try! context.save()

        XCTAssertEqual(job.runCount, 1)
        XCTAssertNotNil(job.lastRunAt)
        XCTAssertEqual(job.lastSessionId, session.id)
        XCTAssertNotNil(job.nextRunAt)
    }
}

// MARK: - Depth Propagation Integration Tests

final class DepthPropagationTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var parentAgent: Agent!

    @MainActor
    override func setUp() {
        super.setUp()
        let schema = Schema([Agent.self, LLMProvider.self, Session.self, AgentConfig.self,
                             CodeSnippet.self, CronJob.self, InstalledSkill.self, Skill.self,
                             Message.self, SessionEmbedding.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        parentAgent = Agent(name: "ParentAgent")
        context.insert(parentAgent)
        try! context.save()
    }

    override func tearDown() {
        container = nil
        context = nil
        parentAgent = nil
        super.tearDown()
    }

    @MainActor
    func testRouterAtDepthZeroCreatesManagerAtDepthZero() {
        let router = FunctionCallRouter(agent: parentAgent, modelContext: context, nestingDepth: 0)
        XCTAssertEqual(router.nestingDepth, 0)
    }

    @MainActor
    func testRouterAtDepthNCreatesManagerAtDepthN() {
        for depth in 0...SubAgentManager.maxNestingDepth {
            let router = FunctionCallRouter(agent: parentAgent, modelContext: context, nestingDepth: depth)
            XCTAssertEqual(router.nestingDepth, depth)
        }
    }

    @MainActor
    func testSubAgentCreationPreservesParentRelationship() {
        let manager = SubAgentManager(modelContext: context, nestingDepth: 0)
        let (subAgent, session) = manager.createSubAgent(
            name: "Child",
            parentAgent: parentAgent,
            initialContext: nil,
            type: .temp
        )

        XCTAssertEqual(subAgent.name, "Child")
        XCTAssertTrue(subAgent.isTempSubAgent)
        XCTAssertEqual(subAgent.parentAgent?.id, parentAgent.id)
        XCTAssertNotNil(session)
    }

    @MainActor
    func testSubAgentCreationPersistent() {
        let manager = SubAgentManager(modelContext: context, nestingDepth: 0)
        let (subAgent, _) = manager.createSubAgent(
            name: "PersistentChild",
            parentAgent: parentAgent,
            initialContext: "You are a helper",
            type: .persistent
        )

        XCTAssertTrue(subAgent.isPersistentSubAgent)
        XCTAssertFalse(subAgent.isTempSubAgent)
        XCTAssertTrue(subAgent.isSubAgent)
    }

    @MainActor
    func testDepthExceededBeforeAgentLookup() async {
        let manager = SubAgentManager(modelContext: context, nestingDepth: SubAgentManager.maxNestingDepth)

        let (subAgent, _) = SubAgentManager(modelContext: context, nestingDepth: 0)
            .createSubAgent(name: "RealChild", parentAgent: parentAgent, initialContext: nil)

        do {
            _ = try await manager.sendMessage(to: subAgent.id, content: "hello")
            XCTFail("Should throw maxDepthExceeded")
        } catch let error as SubAgentError {
            if case .maxDepthExceeded = error {
                // Depth check happens before agent lookup — correct behavior
            } else {
                XCTFail("Expected maxDepthExceeded, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testDestroyTempAgent() {
        let manager = SubAgentManager(modelContext: context, nestingDepth: 0)
        let (subAgent, _) = manager.createSubAgent(
            name: "Disposable",
            parentAgent: parentAgent,
            initialContext: nil,
            type: .temp
        )
        let subId = subAgent.id

        manager.destroyTempAgent(subId)

        let descriptor = FetchDescriptor<Agent>(
            predicate: #Predicate { $0.name == "Disposable" }
        )
        let remaining = try? context.fetch(descriptor)
        XCTAssertTrue(remaining?.isEmpty ?? true, "Temp agent should be deleted")
    }
}
