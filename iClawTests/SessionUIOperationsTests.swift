import XCTest
import SwiftData
@testable import iClaw

// MARK: - Shared Test Schema

private let testSchema = Schema([
    Agent.self, LLMProvider.self, Session.self, AgentConfig.self,
    CodeSnippet.self, CronJob.self, InstalledSkill.self, Skill.self,
    Message.self, SessionEmbedding.self
])

// MARK: - Session Creation & Deletion Tests

final class SessionListOperationsTests: XCTestCase {

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

    // MARK: - Create Session

    @MainActor
    func testCreateSessionReturnsNewSession() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        let session = vm.createSession(agent: agent)

        XCTAssertEqual(session.agent?.name, "TestAgent")
        XCTAssertFalse(session.title.isEmpty)
        XCTAssertFalse(session.isArchived)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.messages.count, 0)
    }

    @MainActor
    func testCreateSessionAppearsInList() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        let countBefore = vm.sessions.count
        _ = vm.createSession(agent: agent)

        XCTAssertEqual(vm.sessions.count, countBefore + 1)
    }

    @MainActor
    func testCreateMultipleSessions() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        let s1 = vm.createSession(agent: agent)
        let s2 = vm.createSession(agent: agent)

        XCTAssertNotEqual(s1.id, s2.id)
        XCTAssertEqual(vm.sessions.count, 2)
    }

    // MARK: - Delete Session

    @MainActor
    func testDeleteSessionRemovesFromList() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        let session = vm.createSession(agent: agent)
        XCTAssertEqual(vm.sessions.count, 1)

        vm.deleteSession(session)
        XCTAssertEqual(vm.sessions.count, 0)
    }

    @MainActor
    func testDeleteSessionCascadesMessages() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "ToDelete", agent: agent)
        context.insert(session)
        for i in 0..<5 {
            let msg = Message(role: .user, content: "msg \(i)", session: session)
            context.insert(msg)
            session.messages.append(msg)
        }
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        vm.deleteSession(session)

        let remaining = (try? context.fetch(FetchDescriptor<Message>())) ?? []
        XCTAssertEqual(remaining.count, 0, "Messages should be cascade-deleted with their Session")
    }

    @MainActor
    func testDeleteSessionAtOffsets() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        _ = vm.createSession(agent: agent)
        _ = vm.createSession(agent: agent)
        _ = vm.createSession(agent: agent)
        XCTAssertEqual(vm.sessions.count, 3)

        vm.deleteSessionAtOffsets(IndexSet(integer: 1))
        XCTAssertEqual(vm.sessions.count, 2)
    }

    // MARK: - Archived Sessions Hidden

    @MainActor
    func testArchivedSessionsNotShownInList() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)

        let visible = Session(title: "Visible", agent: agent)
        context.insert(visible)

        let archived = Session(title: "Archived", agent: agent)
        archived.isArchived = true
        context.insert(archived)

        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        XCTAssertEqual(vm.sessions.count, 1)
        XCTAssertEqual(vm.sessions.first?.title, "Visible")
    }

    // MARK: - Sort Order

    @MainActor
    func testSessionsListSortedByUpdatedAtDescending() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)

        let old = Session(title: "Old", agent: agent)
        old.updatedAt = Date(timeIntervalSince1970: 1000)
        context.insert(old)

        let recent = Session(title: "Recent", agent: agent)
        recent.updatedAt = Date(timeIntervalSince1970: 2000)
        context.insert(recent)

        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        XCTAssertEqual(vm.sessions.first?.title, "Recent")
        XCTAssertEqual(vm.sessions.last?.title, "Old")
    }
}

// MARK: - Session Search / Filter Tests

final class SessionSearchTests: XCTestCase {

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

    @MainActor
    func testSearchByTitle() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)

        let s1 = Session(title: "Swift Programming", agent: agent)
        context.insert(s1)
        let s2 = Session(title: "Python Tutorial", agent: agent)
        context.insert(s2)
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        vm.searchText = "swift"
        vm.applySearch()

        XCTAssertEqual(vm.sessions.count, 1)
        XCTAssertEqual(vm.sessions.first?.title, "Swift Programming")
    }

    @MainActor
    func testSearchByMessageContent() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)

        let s1 = Session(title: "Chat A", agent: agent)
        context.insert(s1)
        let msg = Message(role: .assistant, content: "The answer is 42", session: s1)
        context.insert(msg)
        s1.messages.append(msg)

        let s2 = Session(title: "Chat B", agent: agent)
        context.insert(s2)
        let msg2 = Message(role: .assistant, content: "Hello world", session: s2)
        context.insert(msg2)
        s2.messages.append(msg2)

        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        vm.searchText = "42"
        vm.applySearch()

        XCTAssertEqual(vm.sessions.count, 1)
        XCTAssertEqual(vm.sessions.first?.title, "Chat A")
    }

    @MainActor
    func testSearchByAgentName() {
        let agentA = Agent(name: "CodeHelper")
        context.insert(agentA)
        let agentB = Agent(name: "Writer")
        context.insert(agentB)

        let s1 = Session(title: "Session 1", agent: agentA)
        context.insert(s1)
        let s2 = Session(title: "Session 2", agent: agentB)
        context.insert(s2)
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        vm.searchText = "codehelper"
        vm.applySearch()

        XCTAssertEqual(vm.sessions.count, 1)
        XCTAssertEqual(vm.sessions.first?.title, "Session 1")
    }

    @MainActor
    func testEmptySearchShowsAll() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        for i in 0..<3 {
            let s = Session(title: "Session \(i)", agent: agent)
            context.insert(s)
        }
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        vm.searchText = "test"
        vm.applySearch()
        let filtered = vm.sessions.count

        vm.searchText = ""
        vm.applySearch()
        XCTAssertEqual(vm.sessions.count, 3)
        XCTAssertLessThanOrEqual(filtered, 3)
    }

    @MainActor
    func testWhitespaceOnlySearchShowsAll() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let s = Session(title: "Session", agent: agent)
        context.insert(s)
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        vm.searchText = "   "
        vm.applySearch()

        XCTAssertEqual(vm.sessions.count, 1)
    }
}

// MARK: - Session Row Data Tests

final class SessionRowDataTests: XCTestCase {

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

    @MainActor
    func testRowDataReflectsMessageCount() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        for i in 0..<3 {
            let msg = Message(role: .user, content: "msg \(i)", session: session)
            context.insert(msg)
            session.messages.append(msg)
        }
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        let rowData = vm.rowDataCache[session.id]

        XCTAssertNotNil(rowData)
        XCTAssertEqual(rowData?.messageCount, 3)
    }

    @MainActor
    func testRowDataShowsPreviewFromLastMessage() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)

        let older = Message(role: .user, content: "older message", session: session)
        older.timestamp = Date(timeIntervalSince1970: 100)
        context.insert(older)
        session.messages.append(older)

        let newer = Message(role: .assistant, content: "latest reply", session: session)
        newer.timestamp = Date(timeIntervalSince1970: 200)
        context.insert(newer)
        session.messages.append(newer)

        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        let rowData = vm.rowDataCache[session.id]

        XCTAssertNotNil(rowData?.previewContent)
        XCTAssertTrue(rowData!.previewContent!.contains("latest reply"))
    }

    @MainActor
    func testRowDataDetectsStreamingState() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        session.isActive = true
        session.pendingStreamingContent = "Generating..."
        context.insert(session)
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        let rowData = vm.rowDataCache[session.id]

        XCTAssertEqual(rowData?.isStreaming, true)
    }

    @MainActor
    func testRowDataDetectsDraft() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        session.draftText = "unfinished message..."
        context.insert(session)
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        let rowData = vm.rowDataCache[session.id]

        XCTAssertEqual(rowData?.hasDraft, true)
    }

    @MainActor
    func testRowDataNoDraftWhenEmpty() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        session.draftText = nil
        context.insert(session)
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        let rowData = vm.rowDataCache[session.id]

        XCTAssertEqual(rowData?.hasDraft, false)
    }

    @MainActor
    func testRowDataPreviewTruncatesLongContent() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)

        let longContent = String(repeating: "a", count: 500)
        let msg = Message(role: .assistant, content: longContent, session: session)
        context.insert(msg)
        session.messages.append(msg)
        try! context.save()

        let vm = SessionListViewModel(modelContext: context)
        let preview = vm.rowDataCache[session.id]?.previewContent

        XCTAssertNotNil(preview)
        XCTAssertLessThanOrEqual(preview!.count, 200)
    }
}

// MARK: - Session Rename Tests

final class SessionRenameTests: XCTestCase {

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

    @MainActor
    func testRenameUpdatesTitle() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Original", agent: agent)
        context.insert(session)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.setCustomTitle("Renamed")

        XCTAssertEqual(session.title, "Renamed")
    }

    @MainActor
    func testRenameSetsTitleCustomizedFlag() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Auto Title", agent: agent)
        context.insert(session)
        try! context.save()

        XCTAssertFalse(session.isTitleCustomized)

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.setCustomTitle("User Title")

        XCTAssertTrue(session.isTitleCustomized)
    }

    @MainActor
    func testRenameUpdatesTimestamp() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        session.updatedAt = Date(timeIntervalSince1970: 1000)
        context.insert(session)
        try! context.save()

        let before = session.updatedAt

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.setCustomTitle("New Name")

        XCTAssertGreaterThan(session.updatedAt, before)
    }

    @MainActor
    func testRenameDoesNotAffectMessages() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        let msg = Message(role: .user, content: "hello", session: session)
        context.insert(msg)
        session.messages.append(msg)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.setCustomTitle("New Name")

        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertEqual(vm.messages.first?.content, "hello")
    }

    @MainActor
    func testRenamePerformanceWithManyMessages() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        for i in 0..<100 {
            let msg = Message(role: i % 2 == 0 ? .user : .assistant,
                              content: String(repeating: "x", count: 200),
                              session: session)
            context.insert(msg)
            session.messages.append(msg)
        }
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)

        let start = CFAbsoluteTimeGetCurrent()
        vm.setCustomTitle("Renamed")
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(elapsed, 0.05,
            "Rename should return near-instantly, took \(elapsed)s")
    }

    @MainActor
    func testRenameCachedStatsUnchanged() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        for i in 0..<10 {
            let msg = Message(role: .user, content: "msg \(i)", session: session)
            context.insert(msg)
            session.messages.append(msg)
        }
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        let before = vm.compressionStats

        vm.setCustomTitle("New")

        XCTAssertEqual(vm.compressionStats.totalMessages, before.totalMessages)
        XCTAssertEqual(vm.compressionStats.activeTokens, before.activeTokens)
    }
}

// MARK: - Session Export Tests

final class SessionExportTests: XCTestCase {

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

    @MainActor
    func testExportContainsTitle() {
        let session = Session(title: "My Chat")
        context.insert(session)
        try! context.save()

        let md = SessionExporter.exportToMarkdown(session)
        XCTAssertTrue(md.contains("My Chat"))
    }

    @MainActor
    func testExportContainsAgentName() {
        let agent = Agent(name: "CodeHelper")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        try! context.save()

        let md = SessionExporter.exportToMarkdown(session)
        XCTAssertTrue(md.contains("CodeHelper"))
    }

    @MainActor
    func testExportContainsMessages() {
        let session = Session(title: "Test")
        context.insert(session)

        let userMsg = Message(role: .user, content: "What is Swift?", session: session)
        context.insert(userMsg)
        session.messages.append(userMsg)

        let assistantMsg = Message(role: .assistant, content: "Swift is a programming language.", session: session)
        context.insert(assistantMsg)
        session.messages.append(assistantMsg)

        try! context.save()

        let md = SessionExporter.exportToMarkdown(session)
        XCTAssertTrue(md.contains("What is Swift?"))
        XCTAssertTrue(md.contains("Swift is a programming language."))
    }

    @MainActor
    func testExportContainsYAMLFrontMatter() {
        let session = Session(title: "Test")
        context.insert(session)
        try! context.save()

        let md = SessionExporter.exportToMarkdown(session)
        XCTAssertTrue(md.hasPrefix("---\n"))
        XCTAssertTrue(md.contains("session_id: \(session.id.uuidString)"))
        XCTAssertTrue(md.contains("message_count:"))
    }

    @MainActor
    func testExportContainsCompressedContext() {
        let session = Session(title: "Test")
        session.compressedContext = "Summary of earlier conversation"
        session.compressedUpToIndex = 5
        context.insert(session)
        try! context.save()

        let md = SessionExporter.exportToMarkdown(session)
        XCTAssertTrue(md.contains("Summary of earlier conversation"))
        XCTAssertTrue(md.contains("compressed_messages: 5"))
    }

    @MainActor
    func testExportContainsThinkingContent() {
        let session = Session(title: "Test")
        context.insert(session)

        let msg = Message(role: .assistant, content: "Result", session: session)
        msg.thinkingContent = "Let me think step by step..."
        context.insert(msg)
        session.messages.append(msg)
        try! context.save()

        let md = SessionExporter.exportToMarkdown(session)
        XCTAssertTrue(md.contains("Let me think step by step..."))
    }

    @MainActor
    func testExportFileNameSanitized() {
        let session = Session(title: "Hello, World! @#$%")
        context.insert(session)
        try! context.save()

        let filename = SessionExporter.exportFileName(for: session)
        XCTAssertTrue(filename.hasPrefix("iClaw_"))
        XCTAssertTrue(filename.hasSuffix(".md"))
        XCTAssertFalse(filename.contains("@"))
        XCTAssertFalse(filename.contains("#"))
    }

    @MainActor
    func testExportToFileCreatesReadableFile() {
        let session = Session(title: "Export Test")
        context.insert(session)
        let msg = Message(role: .user, content: "Test content", session: session)
        context.insert(msg)
        session.messages.append(msg)
        try! context.save()

        let url = SessionExporter.exportToFile(session)
        XCTAssertNotNil(url)

        if let url {
            let content = try? String(contentsOf: url, encoding: .utf8)
            XCTAssertNotNil(content)
            XCTAssertTrue(content!.contains("Export Test"))
            XCTAssertTrue(content!.contains("Test content"))
            try? FileManager.default.removeItem(at: url)
        }
    }

    @MainActor
    func testExportMessagesInChronologicalOrder() {
        let session = Session(title: "Test")
        context.insert(session)

        let first = Message(role: .user, content: "FIRST_MESSAGE", session: session)
        first.timestamp = Date(timeIntervalSince1970: 100)
        context.insert(first)
        session.messages.append(first)

        let second = Message(role: .assistant, content: "SECOND_MESSAGE", session: session)
        second.timestamp = Date(timeIntervalSince1970: 200)
        context.insert(second)
        session.messages.append(second)

        try! context.save()

        let md = SessionExporter.exportToMarkdown(session)
        let firstIdx = md.range(of: "FIRST_MESSAGE")!.lowerBound
        let secondIdx = md.range(of: "SECOND_MESSAGE")!.lowerBound
        XCTAssertTrue(firstIdx < secondIdx, "Messages should appear in chronological order")
    }

    @MainActor
    func testExportEmptySession() {
        let session = Session(title: "Empty")
        context.insert(session)
        try! context.save()

        let md = SessionExporter.exportToMarkdown(session)
        XCTAssertTrue(md.contains("Empty"))
        XCTAssertTrue(md.contains("message_count: 0"))
    }
}

// MARK: - ChatViewModel Lifecycle & Draft Tests

final class SessionLifecycleTests: XCTestCase {

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

    // MARK: - Scroll Position Persistence

    @MainActor
    func testSaveScrollPositionPersists() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)

        let msg = Message(role: .user, content: "hello", session: session)
        context.insert(msg)
        session.messages.append(msg)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.saveScrollPosition(msg.id)

        XCTAssertEqual(session.lastViewedMessageId, msg.id)
    }

    @MainActor
    func testScrollPositionRestoredOnInit() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)

        let msg = Message(role: .user, content: "hello", session: session)
        context.insert(msg)
        session.messages.append(msg)
        session.lastViewedMessageId = msg.id
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        XCTAssertEqual(vm.initialScrollTarget, msg.id)
    }

    @MainActor
    func testClearScrollPosition() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        session.lastViewedMessageId = UUID()
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.saveScrollPosition(nil)

        XCTAssertNil(session.lastViewedMessageId)
    }

    // MARK: - Draft Text Persistence

    @MainActor
    func testDraftTextPersistsToSession() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.inputText = "unfinished thought"

        XCTAssertEqual(session.draftText, "unfinished thought")
    }

    @MainActor
    func testEmptyDraftClearsSessionDraft() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        session.draftText = "old draft"
        context.insert(session)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.inputText = "   "

        XCTAssertNil(session.draftText)
    }

    @MainActor
    func testDraftTextRestoredOnInit() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        session.draftText = "saved draft"
        context.insert(session)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        XCTAssertEqual(vm.inputText, "saved draft")
    }

    // MARK: - View Lifecycle

    @MainActor
    func testOnViewAppearLoadsMessages() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        let msg = Message(role: .user, content: "hello", session: session)
        context.insert(msg)
        session.messages.append(msg)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.onViewAppear()

        XCTAssertEqual(vm.messages.count, 1)
    }

    @MainActor
    func testOnViewDisappearSavesDraft() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.inputText = "draft in progress"
        vm.onViewDisappear()

        XCTAssertEqual(session.draftText, "draft in progress")
    }

    // MARK: - Verbose / Silent Mode

    @MainActor
    func testVerboseModeDefaultsFromAgent() {
        let agent = Agent(name: "TestAgent")
        agent.isVerbose = false
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        XCTAssertFalse(vm.isVerbose)
    }

    @MainActor
    func testToggleVerboseUpdatesAgent() {
        let agent = Agent(name: "TestAgent")
        agent.isVerbose = true
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.isVerbose = false

        XCTAssertFalse(agent.isVerbose)
    }

    // MARK: - Active Session Lock

    @MainActor
    func testNoBlockWhenNoOtherActive() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.checkActiveSessionLock()

        XCTAssertNil(vm.sendBlockedReason)
        XCTAssertTrue(vm.canSend)
    }

    // MARK: - Dismiss Retry

    @MainActor
    func testDismissRetryClearsError() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.errorMessage = "Something went wrong"
        vm.canRetry = true

        vm.dismissRetry()

        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.canRetry)
    }

    // MARK: - Cached Agent Properties

    @MainActor
    func testCachedAgentDisplayName() {
        let agent = Agent(name: "SmartAssistant")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        XCTAssertEqual(vm.agentDisplayName, "SmartAssistant")
    }

    @MainActor
    func testCachedImageInputDisabledDefault() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        XCTAssertFalse(vm.isImageInputDisabled)
    }

    @MainActor
    func testNoAgentMeansImageEnabled() {
        let session = Session(title: "Test")
        context.insert(session)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        XCTAssertFalse(vm.isImageInputDisabled)
        XCTAssertNil(vm.agentDisplayName)
    }
}

// MARK: - Session Model Computed Properties Tests

final class SessionModelTests: XCTestCase {

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

    @MainActor
    func testRelatedSessionIdsRoundTrip() {
        let session = Session(title: "Test")
        context.insert(session)

        let ids = [UUID(), UUID(), UUID()]
        session.relatedSessionIds = ids

        XCTAssertEqual(session.relatedSessionIds.count, 3)
        XCTAssertEqual(session.relatedSessionIds, ids)
    }

    @MainActor
    func testRelatedSessionIdsEmptyByDefault() {
        let session = Session(title: "Test")
        context.insert(session)

        XCTAssertTrue(session.relatedSessionIds.isEmpty)
    }

    @MainActor
    func testParentSessionIdRoundTrip() {
        let session = Session(title: "Test")
        context.insert(session)

        let parentId = UUID()
        session.parentSessionId = parentId

        XCTAssertEqual(session.parentSessionId, parentId)
    }

    @MainActor
    func testLastViewedMessageIdRoundTrip() {
        let session = Session(title: "Test")
        context.insert(session)

        let msgId = UUID()
        session.lastViewedMessageId = msgId

        XCTAssertEqual(session.lastViewedMessageId, msgId)
    }

    @MainActor
    func testLastViewedMessageIdNilByDefault() {
        let session = Session(title: "Test")
        context.insert(session)

        XCTAssertNil(session.lastViewedMessageId)
    }

    @MainActor
    func testInitialState() {
        let session = Session(title: "New Chat")
        context.insert(session)

        XCTAssertEqual(session.title, "New Chat")
        XCTAssertFalse(session.isArchived)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(session.isTitleCustomized)
        XCTAssertFalse(session.isCompressingContext)
        XCTAssertEqual(session.messages.count, 0)
        XCTAssertEqual(session.compressedUpToIndex, 0)
        XCTAssertNil(session.compressedContext)
        XCTAssertNil(session.draftText)
        XCTAssertNil(session.pendingStreamingContent)
    }

    @MainActor
    func testSortedMessagesEmpty() {
        let session = Session(title: "Test")
        context.insert(session)

        XCTAssertTrue(session.sortedMessages.isEmpty)
    }

    @MainActor
    func testSortedMessagesByTimestamp() {
        let session = Session(title: "Test")
        context.insert(session)

        let msg1 = Message(role: .user, content: "First", session: session)
        msg1.timestamp = Date(timeIntervalSince1970: 300)
        context.insert(msg1)
        session.messages.append(msg1)

        let msg2 = Message(role: .assistant, content: "Second", session: session)
        msg2.timestamp = Date(timeIntervalSince1970: 100)
        context.insert(msg2)
        session.messages.append(msg2)

        let msg3 = Message(role: .user, content: "Third", session: session)
        msg3.timestamp = Date(timeIntervalSince1970: 200)
        context.insert(msg3)
        session.messages.append(msg3)

        try! context.save()

        let sorted = session.sortedMessages
        XCTAssertEqual(sorted[0].content, "Second")
        XCTAssertEqual(sorted[1].content, "Third")
        XCTAssertEqual(sorted[2].content, "First")
    }
}

// MARK: - Retry Deduplication Tests

final class RetryDeduplicationTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: testSchema, configurations: [config])
        context = ModelContext(container)
    }

    @MainActor
    override func tearDown() {
        if let sessions = try? context.fetch(FetchDescriptor<Session>()) {
            for s in sessions {
                ChatViewModel._clearActiveGeneration(for: s.id)
            }
        }
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Guard: isLoading

    @MainActor
    func testRetryBlockedWhenAlreadyLoading() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.isLoading = true
        vm.canRetry = true
        vm.errorMessage = "some error"

        vm.retryGeneration()

        XCTAssertTrue(vm.canRetry, "canRetry must stay true — retryGeneration was a no-op")
        XCTAssertEqual(vm.errorMessage, "some error", "errorMessage must stay — retryGeneration was a no-op")
    }

    // MARK: - Guard: activeGenerations (cross-VM)

    @MainActor
    func testRetryBlockedByActiveGenerationStaticGuard() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        try! context.save()

        ChatViewModel._simulateActiveGeneration(for: session.id)

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.canRetry = true
        vm.errorMessage = "API error"

        vm.retryGeneration()

        XCTAssertTrue(vm.canRetry, "retryGeneration must be a no-op — generation already active")
        XCTAssertEqual(vm.errorMessage, "API error", "Error must stay — retryGeneration was blocked")
        XCTAssertFalse(vm.isLoading, "isLoading must stay false — retryGeneration was blocked")
    }

    @MainActor
    func testSendBlockedByActiveGenerationStaticGuard() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        try! context.save()

        ChatViewModel._simulateActiveGeneration(for: session.id)

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.inputText = "hello"

        vm.sendMessage()

        XCTAssertFalse(vm.isLoading, "isLoading must stay false — send was blocked")
        XCTAssertEqual(vm.inputText, "hello", "Input must stay — send was blocked")
    }

    @MainActor
    func testRetryPopulatesActiveGenerations() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        try! context.save()

        XCTAssertFalse(ChatViewModel._hasActiveGeneration(for: session.id))

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.retryGeneration()

        XCTAssertTrue(ChatViewModel._hasActiveGeneration(for: session.id),
                       "retryGeneration must register the task in activeGenerations")
    }

    // MARK: - Double-tap on same VM

    @MainActor
    func testDoubleRetryOnSameVMBlocked() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.retryGeneration()

        XCTAssertTrue(vm.isLoading)
        XCTAssertFalse(vm.canRetry)

        vm.canRetry = true
        vm.retryGeneration()

        XCTAssertTrue(vm.canRetry, "Guard short-circuits — canRetry stays true, no state mutation")
        XCTAssertTrue(vm.isLoading, "isLoading unchanged from first call")
    }

    // MARK: - Flags set correctly

    @MainActor
    func testRetrySetsFlagsCorrectly() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.canRetry = true
        vm.errorMessage = "API error"

        vm.retryGeneration()

        XCTAssertTrue(vm.isLoading)
        XCTAssertFalse(vm.canRetry)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Eager session.isActive

    @MainActor
    func testRetryEagerlySetsSessionActive() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        try! context.save()

        XCTAssertFalse(session.isActive)

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.retryGeneration()

        XCTAssertTrue(session.isActive, "session.isActive must be set eagerly before the Task runs")
    }

    @MainActor
    func testSendEagerlySetsSessionActive() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)
        try! context.save()

        XCTAssertFalse(session.isActive)

        let vm = ChatViewModel(session: session, modelContext: context)
        vm.inputText = "hello"
        vm.sendMessage()

        XCTAssertTrue(session.isActive, "session.isActive must be set eagerly before the Task runs")
    }

    // MARK: - Recovery blocked for active session

    @MainActor
    func testRecoverRetryStateBlockedWhenSessionActive() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)

        let msg = Message(role: .user, content: "hello", session: session)
        context.insert(msg)
        session.messages.append(msg)
        session.isActive = true
        try! context.save()

        let vm = ChatViewModel(session: session, modelContext: context)

        XCTAssertFalse(vm.canRetry, "canRetry must not be set when session is active")
    }

    // MARK: - Dismiss prevents recovery across VM recreation

    @MainActor
    func testDismissRetryPreventsRecoveryAcrossVMs() {
        let agent = Agent(name: "TestAgent")
        context.insert(agent)
        let session = Session(title: "Test", agent: agent)
        context.insert(session)

        let msg = Message(role: .user, content: "hello", session: session)
        context.insert(msg)
        session.messages.append(msg)
        try! context.save()

        let vm1 = ChatViewModel(session: session, modelContext: context)
        vm1.canRetry = true
        vm1.dismissRetry()

        let vm2 = ChatViewModel(session: session, modelContext: context)

        XCTAssertFalse(vm2.canRetry, "canRetry must not recover after explicit dismiss")
    }
}
