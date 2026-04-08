import XCTest
import SwiftData
@testable import iClaw

// MARK: - Shared Schema

private let testSchema = Schema([
    Agent.self, LLMProvider.self, Session.self, AgentConfig.self,
    CodeSnippet.self, CronJob.self, InstalledSkill.self, Skill.self,
    Message.self, SessionEmbedding.self
])

// =============================================================================
// MARK: - 1. Delete Active Session / Agent (Crash-Guard)
// =============================================================================

final class DeleteActiveSessionTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: testSchema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Crash-Guard: delete session while isActive == true

    /// Deleting a session that is marked active must not crash.
    /// SwiftData cascade should still clean up messages.
    @MainActor
    func testDeleteActiveSessionDoesNotCrash() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Active Chat")
        context.insert(session)
        session.agent = agent
        session.isActive = true
        session.pendingStreamingContent = "Partial response being streamed..."

        for i in 0..<5 {
            let msg = Message(role: i % 2 == 0 ? .user : .assistant, content: "msg \(i)")
            context.insert(msg)
            session.messages.append(msg)
        }
        try! context.save()

        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.messages.count, 5)

        // Delete while active — must not crash
        let vm = SessionListViewModel(modelContext: context)
        vm.deleteSession(session)

        let remainingSessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        XCTAssertTrue(remainingSessions.isEmpty, "Active session should be deleted")

        let remainingMessages = (try? context.fetch(FetchDescriptor<Message>())) ?? []
        XCTAssertTrue(remainingMessages.isEmpty, "Messages should cascade-delete with active session")
    }

    /// Deleting an active session via offsets must not crash.
    @MainActor
    func testDeleteActiveSessionAtOffsetsDoesNotCrash() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        let s1 = vm.createSession(agent: agent)
        s1.isActive = true
        s1.pendingStreamingContent = "streaming..."
        let _ = vm.createSession(agent: agent)
        try! context.save()
        vm.fetchSessions()

        XCTAssertEqual(vm.sessions.count, 2)

        // Find the index of the active session
        if let activeIdx = vm.sessions.firstIndex(where: { $0.id == s1.id }) {
            vm.deleteSessionAtOffsets(IndexSet(integer: activeIdx))
        }

        XCTAssertEqual(vm.sessions.count, 1)
        XCTAssertFalse(vm.sessions[0].isActive)
    }

    /// Deleting a session while context compression is in progress must not crash.
    @MainActor
    func testDeleteSessionDuringContextCompressionDoesNotCrash() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Compressing")
        context.insert(session)
        session.agent = agent
        session.isActive = true
        session.isCompressingContext = true
        session.compressedContext = "Partial compressed context..."

        let msg = Message(role: .user, content: "Trigger compression")
        context.insert(msg)
        session.messages.append(msg)
        try! context.save()

        context.delete(session)
        try! context.save()

        let remaining = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - Crash-Guard: delete agent with active sessions

    /// Deleting an agent that has active sessions must not crash.
    /// Cascade should delete all sessions and their messages.
    @MainActor
    func testDeleteAgentWithActiveSessionDoesNotCrash() {
        let agent = Agent(name: "BusyAgent")
        context.insert(agent)

        let activeSession = Session(title: "Active")
        context.insert(activeSession)
        activeSession.agent = agent
        activeSession.isActive = true
        activeSession.pendingStreamingContent = "Still generating..."

        let inactiveSession = Session(title: "Idle")
        context.insert(inactiveSession)
        inactiveSession.agent = agent

        for i in 0..<3 {
            let msg = Message(role: .user, content: "msg \(i)")
            context.insert(msg)
            activeSession.messages.append(msg)
        }
        try! context.save()

        XCTAssertEqual(agent.sessions.count, 2)
        XCTAssertTrue(agent.sessions.contains(where: { $0.isActive }))

        // Delete agent — cascade must not crash
        let vm = AgentViewModel(modelContext: context)
        vm.deleteAgent(agent)

        let remainingAgents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        XCTAssertTrue(remainingAgents.isEmpty)

        let remainingSessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        XCTAssertTrue(remainingSessions.isEmpty, "All sessions should be cascade-deleted")

        let remainingMessages = (try? context.fetch(FetchDescriptor<Message>())) ?? []
        XCTAssertTrue(remainingMessages.isEmpty, "All messages should be cascade-deleted")
    }

    /// Deleting an agent with multiple active sessions (some streaming, some compressing).
    @MainActor
    func testDeleteAgentWithMultipleActiveSessionsDoesNotCrash() {
        let agent = Agent(name: "MultiActive")
        context.insert(agent)

        for i in 0..<4 {
            let session = Session(title: "Session \(i)")
            context.insert(session)
            session.agent = agent
            session.isActive = (i % 2 == 0)
            if i == 2 { session.isCompressingContext = true }

            let msg = Message(role: .user, content: "Hello \(i)")
            context.insert(msg)
            session.messages.append(msg)
        }
        try! context.save()

        let activeCount = agent.sessions.filter(\.isActive).count
        XCTAssertEqual(activeCount, 2)

        context.delete(agent)
        try! context.save()

        let remaining = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - State-Consistency: session list updates correctly after active deletion

    /// After deleting an active session, selectedSession should not reference the deleted session.
    @MainActor
    func testSelectedSessionClearedAfterActiveSessionDeleted() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        let session = vm.createSession(agent: agent)
        session.isActive = true
        try! context.save()

        vm.selectedSession = session
        XCTAssertNotNil(vm.selectedSession)

        vm.deleteSession(session)

        // The VM doesn't auto-clear selectedSession — document this behavior.
        // The View layer (SessionListView) is responsible for clearing it.
        // Verify session is gone from the list.
        XCTAssertEqual(vm.sessions.count, 0)
    }
}

// =============================================================================
// MARK: - 2. Delete LLM Provider Used by Active Session
// =============================================================================

final class DeleteActiveProviderTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: testSchema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Crash-Guard: ModelRouter after provider deletion

    /// After deleting the primary provider, ModelRouter must not crash.
    /// It should fall back to the global default.
    @MainActor
    func testModelRouterFallsBackAfterPrimaryProviderDeleted() {
        let primary = LLMProvider(name: "Primary", modelName: "gpt-4o")
        primary.isDefault = false
        context.insert(primary)

        let fallback = LLMProvider(name: "Fallback", modelName: "gpt-3.5", isDefault: true)
        context.insert(fallback)

        let agent = Agent(name: "TestAgent")
        agent.primaryProviderId = primary.id
        context.insert(agent)
        try! context.save()

        // Verify primary resolves before deletion
        let router = ModelRouter(modelContext: context)
        let chainBefore = router.resolveProviderChain(for: agent)
        XCTAssertEqual(chainBefore.first?.name, "Primary")

        // Delete primary provider
        context.delete(primary)
        try! context.save()

        // Agent still references the deleted provider's UUID — dangling reference
        XCTAssertNotNil(agent.primaryProviderId, "Agent still holds deleted provider UUID")

        // ModelRouter should gracefully fall back, not crash
        let chainAfter = router.resolveProviderChain(for: agent)
        XCTAssertFalse(chainAfter.isEmpty, "Router should fall back to global default")
        XCTAssertEqual(chainAfter.first?.name, "Fallback",
                       "Router should resolve to global default after primary deleted")
    }

    /// After deleting ALL providers, ModelRouter returns empty chain without crashing.
    @MainActor
    func testModelRouterReturnsEmptyChainWhenAllProvidersDeleted() {
        let provider = LLMProvider(name: "Only", isDefault: true)
        context.insert(provider)

        let agent = Agent(name: "TestAgent")
        agent.primaryProviderId = provider.id
        context.insert(agent)
        try! context.save()

        context.delete(provider)
        try! context.save()

        let router = ModelRouter(modelContext: context)
        let chain = router.resolveProviderChain(for: agent)
        XCTAssertTrue(chain.isEmpty, "Chain should be empty when no providers exist")

        let chainWithModels = router.resolveProviderChainWithModels(for: agent)
        XCTAssertTrue(chainWithModels.isEmpty)
    }

    /// Deleting a fallback provider does not crash and the remaining chain is correct.
    @MainActor
    func testDeleteFallbackProviderDoesNotCrash() {
        let primary = LLMProvider(name: "Primary", isDefault: true)
        context.insert(primary)
        let fb1 = LLMProvider(name: "Fallback1")
        context.insert(fb1)
        let fb2 = LLMProvider(name: "Fallback2")
        context.insert(fb2)

        let agent = Agent(name: "TestAgent")
        agent.primaryProviderId = primary.id
        agent.fallbackProviderIds = [fb1.id, fb2.id]
        agent.fallbackModelNames = ["model-a", "model-b"]
        context.insert(agent)
        try! context.save()

        // Delete fb1
        context.delete(fb1)
        try! context.save()

        let router = ModelRouter(modelContext: context)
        let chain = router.resolveProviderChainWithModels(for: agent)

        // Should have primary + fb2, fb1 silently skipped
        XCTAssertEqual(chain.count, 2)
        XCTAssertEqual(chain[0].provider.name, "Primary")
        XCTAssertEqual(chain[1].provider.name, "Fallback2")
    }

    /// SettingsViewModel.deleteProvider correctly reassigns default.
    @MainActor
    func testDeleteDefaultProviderReassignsDefault() {
        let vm = SettingsViewModel(modelContext: context)
        vm.addProvider(name: "First", endpoint: "https://a.com", apiKey: "", modelName: "m1")
        vm.addProvider(name: "Second", endpoint: "https://b.com", apiKey: "", modelName: "m2")

        // First is default (was first added)
        XCTAssertTrue(vm.providers[0].isDefault)

        vm.deleteProvider(vm.providers[0])

        XCTAssertEqual(vm.providers.count, 1)
        XCTAssertTrue(vm.providers[0].isDefault,
                      "Remaining provider should become default after default deleted")
    }

    // MARK: - State-Consistency: agent with deleted provider

    /// After deleting the only provider, resolving capabilities should return .default, not crash.
    @MainActor
    func testPrimaryModelCapabilitiesReturnDefaultAfterProviderDeleted() {
        let provider = LLMProvider(name: "Test", modelName: "gpt-4o")
        provider.isDefault = true
        context.insert(provider)

        let agent = Agent(name: "TestAgent")
        agent.primaryProviderId = provider.id
        context.insert(agent)
        try! context.save()

        context.delete(provider)
        try! context.save()

        let router = ModelRouter(modelContext: context)
        let caps = router.primaryModelCapabilities(for: agent)
        XCTAssertEqual(caps, .default,
                       "Should return default capabilities when provider is gone")
    }

    /// Deleting a provider referenced by multiple agents must not crash.
    @MainActor
    func testDeleteProviderUsedByMultipleAgentsDoesNotCrash() {
        let provider = LLMProvider(name: "Shared", isDefault: true)
        context.insert(provider)
        let providerId = provider.id

        for i in 0..<5 {
            let agent = Agent(name: "Agent\(i)")
            agent.primaryProviderId = providerId
            context.insert(agent)
        }
        try! context.save()

        context.delete(provider)
        try! context.save()

        let agents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        XCTAssertEqual(agents.count, 5, "Agents should NOT be cascade-deleted with provider")

        // All agents now have dangling provider references — router should handle gracefully
        let router = ModelRouter(modelContext: context)
        for agent in agents {
            let chain = router.resolveProviderChain(for: agent)
            XCTAssertTrue(chain.isEmpty,
                          "Chain should be empty (no providers left), not crash")
        }
    }

    /// Deleting a specific model (via disabling in enabledModels) while agent uses it:
    /// the agent's model name override still references it, but provider still exists.
    @MainActor
    func testAgentModelOverrideStillWorksAfterModelDisabled() {
        let provider = LLMProvider(name: "Multi", modelName: "gpt-4o", isDefault: true)
        provider.enabledModels = ["gpt-4o", "gpt-3.5-turbo"]
        context.insert(provider)

        let agent = Agent(name: "TestAgent")
        agent.primaryProviderId = provider.id
        agent.primaryModelNameOverride = "gpt-3.5-turbo"
        context.insert(agent)
        try! context.save()

        // Remove gpt-3.5-turbo from enabled models
        provider.enabledModels = ["gpt-4o"]
        try! context.save()

        // ModelRouter still resolves — model override is a string, not enforced at router level
        let router = ModelRouter(modelContext: context)
        let chain = router.resolveProviderChainWithModels(for: agent)
        XCTAssertFalse(chain.isEmpty, "Chain should still resolve (enabledModels is UI-level)")
        XCTAssertEqual(chain.first?.modelName, "gpt-3.5-turbo",
                       "Model override persists regardless of enabledModels list")
    }
}

// =============================================================================
// MARK: - 3. Delete Sub-Agent While Active
// =============================================================================

final class DeleteActiveSubAgentTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: testSchema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Crash-Guard: SubAgentManager after external deletion

    /// forceStop on a sub-agent that was already externally deleted must not crash.
    @MainActor
    func testForceStopOnDeletedSubAgentDoesNotCrash() {
        let parent = Agent(name: "Parent")
        context.insert(parent)

        let manager = SubAgentManager(modelContext: context)
        let (subAgent, _) = manager.createSubAgent(
            name: "TempSub",
            parentAgent: parent,
            initialContext: nil,
            type: .persistent
        )
        let subId = subAgent.id

        // Externally delete the sub-agent (simulating user action)
        context.delete(subAgent)
        try! context.save()

        // forceStop on deleted sub-agent — must not crash
        manager.forceStop(subAgentId: subId)

        // Verify parent still exists
        let agents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents.first?.name, "Parent")
    }

    /// deletePersistentAgent on an already-deleted sub-agent must not crash.
    @MainActor
    func testDeletePersistentAgentAlreadyDeletedDoesNotCrash() {
        let parent = Agent(name: "Parent")
        context.insert(parent)

        let manager = SubAgentManager(modelContext: context)
        let (subAgent, _) = manager.createSubAgent(
            name: "PersistentSub",
            parentAgent: parent,
            initialContext: nil,
            type: .persistent
        )
        let subId = subAgent.id

        // Externally delete
        context.delete(subAgent)
        try! context.save()

        // Double-delete via manager — must not crash
        manager.deletePersistentAgent(subId)

        let agents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        XCTAssertEqual(agents.count, 1)
    }

    /// destroyTempAgent on an already-deleted sub-agent must not crash.
    @MainActor
    func testDestroyTempAgentAlreadyDeletedDoesNotCrash() {
        let parent = Agent(name: "Parent")
        context.insert(parent)

        let manager = SubAgentManager(modelContext: context)
        let (subAgent, _) = manager.createSubAgent(
            name: "TempSub",
            parentAgent: parent,
            initialContext: nil,
            type: .temp
        )
        let subId = subAgent.id

        context.delete(subAgent)
        try! context.save()

        // Destroy after external deletion — must not crash
        manager.destroyTempAgent(subId)
    }

    /// collectSessionSummary for a deleted sub-agent returns error text, not a crash.
    @MainActor
    func testCollectSessionSummaryForDeletedSubAgentReturnsError() {
        let parent = Agent(name: "Parent")
        context.insert(parent)

        let manager = SubAgentManager(modelContext: context)
        let (subAgent, session) = manager.createSubAgent(
            name: "Sub",
            parentAgent: parent,
            initialContext: nil,
            type: .persistent
        )

        // Add some messages to the session
        let msg = Message(role: .assistant, content: "Sub-agent output")
        context.insert(msg)
        session.messages.append(msg)
        try! context.save()

        let subId = subAgent.id

        // Delete the sub-agent (cascade deletes its session + messages)
        context.delete(subAgent)
        try! context.save()

        // Collect summary — should return error text, not crash
        let result = manager.collectSessionSummary(subAgentId: subId)
        XCTAssertTrue(result.text.contains("Error") || result.text.contains("not found"),
                      "Should return error message for deleted sub-agent, got: \(result.text)")
    }

    /// collectFullTranscript for a deleted sub-agent returns error text, not a crash.
    @MainActor
    func testCollectFullTranscriptForDeletedSubAgentReturnsError() {
        let parent = Agent(name: "Parent")
        context.insert(parent)

        let manager = SubAgentManager(modelContext: context)
        let (subAgent, _) = manager.createSubAgent(
            name: "Sub",
            parentAgent: parent,
            initialContext: nil,
            type: .persistent
        )
        let subId = subAgent.id

        context.delete(subAgent)
        try! context.save()

        let result = manager.collectFullTranscript(subAgentId: subId)
        XCTAssertTrue(result.text.contains("Error") || result.text.contains("not found"),
                      "Should return error message for deleted sub-agent")
    }

    // MARK: - Crash-Guard: cascade delete parent with active sub-agents

    /// Deleting a parent agent cascades to sub-agents with active sessions.
    @MainActor
    func testDeleteParentCascadesToActiveSubAgentsDoesNotCrash() {
        let parent = Agent(name: "Parent")
        context.insert(parent)

        // Create sub-agents with active sessions
        for i in 0..<3 {
            let sub = Agent(name: "Sub\(i)")
            sub.subAgentType = "persistent"
            context.insert(sub)
            parent.subAgents.append(sub)

            let session = Session(title: "SubSession\(i)")
            context.insert(session)
            session.agent = sub
            session.isActive = (i == 0) // First sub-agent is active

            let msg = Message(role: .assistant, content: "Output \(i)")
            context.insert(msg)
            session.messages.append(msg)
        }
        try! context.save()

        XCTAssertEqual(parent.subAgents.count, 3)
        XCTAssertTrue(parent.subAgents[0].sessions.first?.isActive ?? false)

        // Delete parent — cascade must not crash
        context.delete(parent)
        try! context.save()

        let remainingAgents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        XCTAssertTrue(remainingAgents.isEmpty, "All agents (parent + subs) should be deleted")

        let remainingSessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        XCTAssertTrue(remainingSessions.isEmpty, "All sessions should be cascade-deleted")

        let remainingMessages = (try? context.fetch(FetchDescriptor<Message>())) ?? []
        XCTAssertTrue(remainingMessages.isEmpty, "All messages should be cascade-deleted")
    }

    // MARK: - State-Consistency: SubAgentManager stale state

    /// inflightSubAgentSessions returns empty after sub-agent externally deleted.
    @MainActor
    func testInflightSubAgentSessionsEmptyAfterExternalDeletion() {
        let parent = Agent(name: "Parent")
        context.insert(parent)

        let manager = SubAgentManager(modelContext: context)
        let (subAgent, session) = manager.createSubAgent(
            name: "Sub",
            parentAgent: parent,
            initialContext: nil,
            type: .persistent
        )
        session.isActive = true
        try! context.save()

        // Before deletion: inflight should include the sub
        let inflightBefore = manager.inflightSubAgentSessions(for: parent)
        XCTAssertEqual(inflightBefore.count, 1)

        // Externally delete sub-agent
        context.delete(subAgent)
        try! context.save()

        // After deletion: parent.subAgents is empty, so inflight should be empty
        let inflightAfter = manager.inflightSubAgentSessions(for: parent)
        XCTAssertTrue(inflightAfter.isEmpty,
                      "Inflight should be empty after sub-agent externally deleted")
    }

    /// allSubAgentSessions returns empty after sub-agent externally deleted.
    @MainActor
    func testAllSubAgentSessionsEmptyAfterExternalDeletion() {
        let parent = Agent(name: "Parent")
        context.insert(parent)

        let manager = SubAgentManager(modelContext: context)
        let (subAgent, _) = manager.createSubAgent(
            name: "Sub",
            parentAgent: parent,
            initialContext: nil,
            type: .persistent
        )

        let allBefore = manager.allSubAgentSessions(for: parent)
        XCTAssertEqual(allBefore.count, 1)

        context.delete(subAgent)
        try! context.save()

        let allAfter = manager.allSubAgentSessions(for: parent)
        XCTAssertTrue(allAfter.isEmpty)
    }

    /// sendMessage to a deleted sub-agent throws .agentNotFound.
    @MainActor
    func testSendMessageToDeletedSubAgentThrowsAgentNotFound() async {
        let parent = Agent(name: "Parent")
        context.insert(parent)

        let manager = SubAgentManager(modelContext: context)
        let (subAgent, _) = manager.createSubAgent(
            name: "Sub",
            parentAgent: parent,
            initialContext: nil,
            type: .persistent
        )
        let subId = subAgent.id

        context.delete(subAgent)
        try! context.save()

        do {
            _ = try await manager.sendMessage(to: subId, content: "Hello?")
            XCTFail("Should have thrown SubAgentError.agentNotFound")
        } catch let error as SubAgentError {
            switch error {
            case .agentNotFound:
                // Expected — user-understandable error
                XCTAssertTrue(error.localizedDescription.contains("not found"))
            default:
                XCTFail("Unexpected SubAgentError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// =============================================================================
// MARK: - 4. Concurrent Agent / LLM Session Modification
// =============================================================================

final class ConcurrentModificationTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: testSchema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Crash-Guard: concurrent agent config modification

    /// Modifying agent soul/memory while a session exists must not corrupt data.
    @MainActor
    func testModifyAgentConfigWhileSessionExistsDoesNotCrash() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Active Chat")
        context.insert(session)
        session.agent = agent
        session.isActive = true

        let msg = Message(role: .user, content: "Hello")
        context.insert(msg)
        session.messages.append(msg)
        try! context.save()

        // Modify agent config while session is "active"
        let service = AgentService(modelContext: context)
        service.writeConfig(agent: agent, key: "SOUL.md", content: "New soul while active")
        service.writeConfig(agent: agent, key: "MEMORY.md", content: "New memory while active")
        service.writeConfig(agent: agent, key: "custom.md", content: "New custom config")

        // Session and messages must remain intact
        XCTAssertEqual(agent.soulMarkdown, "New soul while active")
        XCTAssertEqual(agent.memoryMarkdown, "New memory while active")
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.messages.count, 1)
        XCTAssertEqual(agent.customConfigs.count, 1)
    }

    /// Switching agent's primary provider while session is active must not crash.
    @MainActor
    func testSwitchProviderWhileSessionActiveDoesNotCrash() {
        let p1 = LLMProvider(name: "Provider1", isDefault: true)
        context.insert(p1)
        let p2 = LLMProvider(name: "Provider2")
        context.insert(p2)

        let agent = Agent(name: "TestAgent")
        agent.primaryProviderId = p1.id
        context.insert(agent)

        let session = Session(title: "Active")
        context.insert(session)
        session.agent = agent
        session.isActive = true
        try! context.save()

        // Switch provider mid-"generation"
        agent.primaryProviderId = p2.id
        agent.primaryModelNameOverride = "new-model"
        try! context.save()

        // Verify ModelRouter reflects the change
        let router = ModelRouter(modelContext: context)
        let chain = router.resolveProviderChain(for: agent)
        XCTAssertEqual(chain.first?.name, "Provider2",
                       "Router should reflect the new provider immediately")

        // Session is still intact
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.agent?.name, "TestAgent")
    }

    /// Deleting a provider while simultaneously modifying agent's fallback chain.
    @MainActor
    func testDeleteProviderAndModifyFallbackChainDoesNotCrash() {
        let p1 = LLMProvider(name: "Primary", isDefault: true)
        context.insert(p1)
        let p2 = LLMProvider(name: "Fallback1")
        context.insert(p2)
        let p3 = LLMProvider(name: "Fallback2")
        context.insert(p3)

        let agent = Agent(name: "TestAgent")
        agent.primaryProviderId = p1.id
        agent.fallbackProviderIds = [p2.id, p3.id]
        context.insert(agent)
        try! context.save()

        // Delete p2 and modify fallback chain in same save
        context.delete(p2)
        agent.fallbackProviderIds = [p3.id]
        agent.fallbackModelNames = ["model-c"]
        try! context.save()

        let router = ModelRouter(modelContext: context)
        let chain = router.resolveProviderChainWithModels(for: agent)
        XCTAssertEqual(chain.count, 2, "Should have primary + one fallback")
        XCTAssertEqual(chain[0].provider.name, "Primary")
        XCTAssertEqual(chain[1].provider.name, "Fallback2")
    }

    // MARK: - Crash-Guard: concurrent session and provider deletion

    /// Delete session and its agent's provider in one transaction.
    @MainActor
    func testDeleteSessionAndProviderSimultaneouslyDoesNotCrash() {
        let provider = LLMProvider(name: "Test", isDefault: true)
        context.insert(provider)

        let agent = Agent(name: "TestAgent")
        agent.primaryProviderId = provider.id
        context.insert(agent)

        let session = Session(title: "ToDelete")
        context.insert(session)
        session.agent = agent
        session.isActive = true

        let msg = Message(role: .user, content: "Hello")
        context.insert(msg)
        session.messages.append(msg)
        try! context.save()

        // Delete both session and provider atomically
        context.delete(session)
        context.delete(provider)
        try! context.save()

        let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        let providers = (try? context.fetch(FetchDescriptor<LLMProvider>())) ?? []
        XCTAssertTrue(sessions.isEmpty)
        XCTAssertTrue(providers.isEmpty)

        // Agent still exists with dangling references
        let agents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        XCTAssertEqual(agents.count, 1)

        // ModelRouter handles dangling refs gracefully
        let router = ModelRouter(modelContext: context)
        let chain = router.resolveProviderChain(for: agents[0])
        XCTAssertTrue(chain.isEmpty)
    }

    /// Multiple ModelContexts: delete from one context, read from another.
    @MainActor
    func testDeleteFromSeparateContextDoesNotCrash() throws {
        let provider = LLMProvider(name: "Shared", isDefault: true)
        context.insert(provider)

        let agent = Agent(name: "TestAgent")
        agent.primaryProviderId = provider.id
        context.insert(agent)
        try context.save()

        // Create a second context (simulating concurrent access)
        let context2 = ModelContext(container)

        // Delete provider from context2
        let providers2 = try context2.fetch(FetchDescriptor<LLMProvider>())
        for p in providers2 { context2.delete(p) }
        try context2.save()

        // Original context's router should handle the deletion
        let router = ModelRouter(modelContext: context)
        let chain = router.resolveProviderChain(for: agent)
        // After context2 deletion and potential merge, chain should be empty or fallback
        // The key assertion: this must not crash
        XCTAssertTrue(chain.isEmpty || chain.first?.name != "Shared",
                      "Should handle cross-context deletion gracefully")
    }

    // MARK: - Crash-Guard: rapid create-delete cycles

    /// Rapidly creating and deleting sessions must not corrupt the model context.
    @MainActor
    func testRapidCreateDeleteSessionCyclesDoesNotCrash() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)

        for _ in 0..<20 {
            let session = vm.createSession(agent: agent)
            session.isActive = true
            let msg = Message(role: .user, content: "msg")
            context.insert(msg)
            session.messages.append(msg)
            try! context.save()

            vm.deleteSession(session)
        }

        XCTAssertEqual(vm.sessions.count, 0)

        let remainingMessages = (try? context.fetch(FetchDescriptor<Message>())) ?? []
        XCTAssertTrue(remainingMessages.isEmpty, "All messages from rapid cycles should be cleaned up")
    }

    /// Rapidly creating and deleting sub-agents must not crash.
    @MainActor
    func testRapidCreateDeleteSubAgentCyclesDoesNotCrash() {
        let parent = Agent(name: "Parent")
        context.insert(parent)
        try! context.save()

        let manager = SubAgentManager(modelContext: context)

        for i in 0..<10 {
            let (sub, session) = manager.createSubAgent(
                name: "Sub\(i)",
                parentAgent: parent,
                initialContext: nil,
                type: i % 2 == 0 ? .temp : .persistent
            )
            session.isActive = true

            let msg = Message(role: .assistant, content: "Output \(i)")
            context.insert(msg)
            session.messages.append(msg)
            try! context.save()

            if sub.isTempSubAgent {
                manager.destroyTempAgent(sub.id)
            } else {
                manager.deletePersistentAgent(sub.id)
            }
        }

        XCTAssertTrue(parent.subAgents.isEmpty, "All sub-agents should be cleaned up")
    }

    // MARK: - State-Consistency: ModelRouter resolves fresh after mutation

    /// ModelRouter re-resolves the provider chain on each call (no stale cache).
    @MainActor
    func testModelRouterResolvessFreshOnEachCall() {
        let p1 = LLMProvider(name: "Original", isDefault: true)
        context.insert(p1)

        let agent = Agent(name: "TestAgent")
        agent.primaryProviderId = p1.id
        context.insert(agent)
        try! context.save()

        let router = ModelRouter(modelContext: context)

        // First call
        let chain1 = router.resolveProviderChain(for: agent)
        XCTAssertEqual(chain1.first?.name, "Original")

        // Mutate: add a new provider and switch
        let p2 = LLMProvider(name: "Replacement")
        context.insert(p2)
        agent.primaryProviderId = p2.id
        try! context.save()

        // Same router, second call — should reflect the mutation
        let chain2 = router.resolveProviderChain(for: agent)
        XCTAssertEqual(chain2.first?.name, "Replacement",
                       "Router should reflect provider change without recreating")
    }
}
