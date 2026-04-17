import XCTest
import SwiftData
@testable import iClaw

final class SkillToolsEditTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        let schema = Schema([Agent.self, LLMProvider.self, Session.self, AgentConfig.self,
                             CodeSnippet.self, CronJob.self, InstalledSkill.self, Skill.self,
                             Message.self])
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
    private func makeAgent(name: String = "Agent") -> Agent {
        let a = Agent(name: name)
        context.insert(a)
        try! context.save()
        return a
    }

    @MainActor
    private func makeSkill(
        name: String = "Test Skill",
        scripts: [SkillScript] = [],
        customTools: [SkillToolDefinition] = [],
        isBuiltIn: Bool = false
    ) -> Skill {
        let skill = Skill(
            name: name,
            summary: "summary",
            content: "content",
            tags: ["t"],
            isBuiltIn: isBuiltIn,
            scripts: scripts,
            customTools: customTools
        )
        context.insert(skill)
        try! context.save()
        return skill
    }

    // MARK: - Metadata updates

    @MainActor
    func testEditSkillUpdatesMetadata() {
        let agent = makeAgent()
        let skill = makeSkill()
        let tools = SkillTools(agent: agent, modelContext: context)

        let result = tools.editSkill(arguments: [
            "name": "Test Skill",
            "new_name": "Renamed Skill",
            "summary": "new summary",
            "content": "new content",
            "tags": "one, two, three"
        ])

        XCTAssertFalse(result.contains("[Error]"), result)
        XCTAssertEqual(skill.name, "Renamed Skill")
        XCTAssertEqual(skill.nameLowercase, "renamed skill")
        XCTAssertEqual(skill.summary, "new summary")
        XCTAssertEqual(skill.content, "new content")
        XCTAssertEqual(skill.tags, ["one", "two", "three"])
    }

    @MainActor
    func testEditSkillRejectsDuplicateName() {
        let agent = makeAgent()
        _ = makeSkill(name: "Existing")
        let skill = makeSkill(name: "Other")
        let tools = SkillTools(agent: agent, modelContext: context)

        let result = tools.editSkill(arguments: [
            "skill_id": skill.id.uuidString,
            "new_name": "Existing"
        ])

        XCTAssertTrue(result.contains("[Error]"), result)
        XCTAssertTrue(result.contains("already exists"), result)
        XCTAssertEqual(skill.name, "Other", "Name should not change on conflict")
    }

    @MainActor
    func testEditSkillRejectsBuiltIn() {
        let agent = makeAgent()
        let skill = makeSkill(name: "BI", isBuiltIn: true)
        let tools = SkillTools(agent: agent, modelContext: context)

        let result = tools.editSkill(arguments: [
            "skill_id": skill.id.uuidString,
            "summary": "hacked"
        ])

        XCTAssertTrue(result.contains("[Error]"), result)
        XCTAssertTrue(result.contains("built-in"), result)
        XCTAssertEqual(skill.summary, "summary")
    }

    @MainActor
    func testEditSkillRequiresAtLeastOneField() {
        let agent = makeAgent()
        let skill = makeSkill()
        let tools = SkillTools(agent: agent, modelContext: context)

        let result = tools.editSkill(arguments: [
            "skill_id": skill.id.uuidString
        ])

        XCTAssertTrue(result.contains("[Error]"), result)
        XCTAssertTrue(result.contains("Nothing to update"), result)
    }

    @MainActor
    func testEditSkillNotFound() {
        let agent = makeAgent()
        let tools = SkillTools(agent: agent, modelContext: context)

        let result = tools.editSkill(arguments: [
            "name": "Does Not Exist",
            "summary": "x"
        ])

        XCTAssertTrue(result.contains("[Error]"), result)
    }

    // MARK: - Scripts replacement & CodeSnippet sync

    @MainActor
    func testEditSkillReplacesScriptsAndResyncsInstalledAgent() throws {
        let agent = makeAgent()
        let skill = makeSkill(scripts: [
            SkillScript(name: "old", language: "javascript", code: "console.log('old');")
        ])

        // Install the skill so there's a CodeSnippet to resync.
        let service = SkillService(modelContext: context)
        _ = service.installSkill(skill, on: agent)
        XCTAssertTrue(agent.codeSnippets.contains { $0.name == "skill:Test Skill:old" })

        let tools = SkillTools(agent: agent, modelContext: context)
        let newScriptsJson = """
        [{"name":"fresh","language":"python","code":"print('fresh')","description":"d"}]
        """
        let result = tools.editSkill(arguments: [
            "skill_id": skill.id.uuidString,
            "scripts": newScriptsJson
        ])

        XCTAssertFalse(result.contains("[Error]"), result)
        XCTAssertEqual(skill.scripts.count, 1)
        XCTAssertEqual(skill.scripts.first?.name, "fresh")
        XCTAssertEqual(skill.scripts.first?.language, "python")

        // Old snippet gone, new snippet registered with matching fields.
        XCTAssertFalse(agent.codeSnippets.contains { $0.name == "skill:Test Skill:old" })
        let fresh = agent.codeSnippets.first { $0.name == "skill:Test Skill:fresh" }
        XCTAssertNotNil(fresh)
        XCTAssertEqual(fresh?.language, "python")
        XCTAssertEqual(fresh?.code, "print('fresh')")
    }

    @MainActor
    func testEditSkillEmptyScriptsArrayClearsSnippets() {
        let agent = makeAgent()
        let skill = makeSkill(scripts: [
            SkillScript(name: "s1", code: "a();"),
            SkillScript(name: "s2", code: "b();")
        ])
        let service = SkillService(modelContext: context)
        _ = service.installSkill(skill, on: agent)
        XCTAssertEqual(agent.codeSnippets.filter { $0.name.hasPrefix("skill:Test Skill:") }.count, 2)

        let tools = SkillTools(agent: agent, modelContext: context)
        let result = tools.editSkill(arguments: [
            "skill_id": skill.id.uuidString,
            "scripts": "[]"
        ])

        XCTAssertFalse(result.contains("[Error]"), result)
        XCTAssertTrue(skill.scripts.isEmpty)
        XCTAssertTrue(agent.codeSnippets.filter { $0.name.hasPrefix("skill:Test Skill:") }.isEmpty)
    }

    @MainActor
    func testEditSkillRenameResyncsSnippetPrefix() {
        let agent = makeAgent()
        let skill = makeSkill(name: "Alpha", scripts: [
            SkillScript(name: "s", code: "x();")
        ])
        let service = SkillService(modelContext: context)
        _ = service.installSkill(skill, on: agent)
        XCTAssertTrue(agent.codeSnippets.contains { $0.name == "skill:Alpha:s" })

        let tools = SkillTools(agent: agent, modelContext: context)
        let result = tools.editSkill(arguments: [
            "skill_id": skill.id.uuidString,
            "new_name": "Beta"
        ])

        XCTAssertFalse(result.contains("[Error]"), result)
        XCTAssertFalse(agent.codeSnippets.contains { $0.name == "skill:Alpha:s" })
        XCTAssertTrue(agent.codeSnippets.contains { $0.name == "skill:Beta:s" })
    }

    // MARK: - Custom tools replacement

    @MainActor
    func testEditSkillReplacesCustomTools() throws {
        let agent = makeAgent()
        let skill = makeSkill(customTools: [
            SkillToolDefinition(name: "old_tool", description: "old", implementation: "return 1;")
        ])

        let tools = SkillTools(agent: agent, modelContext: context)
        let newToolsJson = """
        [{"name":"greet","description":"say hi","parameters":[{"name":"who","type":"string","description":"person","required":true}],"implementation":"console.log('hi '+args.who);"}]
        """
        let result = tools.editSkill(arguments: [
            "skill_id": skill.id.uuidString,
            "tools": newToolsJson
        ])

        XCTAssertFalse(result.contains("[Error]"), result)
        XCTAssertEqual(skill.customTools.count, 1)
        XCTAssertEqual(skill.customTools.first?.name, "greet")
        XCTAssertEqual(skill.customTools.first?.parameters.first?.name, "who")
        XCTAssertEqual(skill.customTools.first?.parameters.first?.required, true)
    }

    // MARK: - Invalid JSON

    @MainActor
    func testEditSkillRejectsInvalidScriptsJson() {
        let agent = makeAgent()
        let skill = makeSkill()
        let tools = SkillTools(agent: agent, modelContext: context)

        let result = tools.editSkill(arguments: [
            "skill_id": skill.id.uuidString,
            "scripts": "not json"
        ])

        XCTAssertTrue(result.contains("[Error]"), result)
        XCTAssertTrue(result.contains("scripts"), result)
    }

    @MainActor
    func testEditSkillRejectsInvalidToolsJson() {
        let agent = makeAgent()
        let skill = makeSkill()
        let tools = SkillTools(agent: agent, modelContext: context)

        let result = tools.editSkill(arguments: [
            "skill_id": skill.id.uuidString,
            "tools": "{not an array}"
        ])

        XCTAssertTrue(result.contains("[Error]"), result)
        XCTAssertTrue(result.contains("tools"), result)
    }
}
