import XCTest
@testable import iClaw

/// Verifies that loading the shipped built-in skills from disk produces the
/// same `ResolvedTemplate` shape as the legacy Swift-string templates.
///
/// This is the Phase 2 acceptance contract — when these tests pass we have
/// proven the directory-based loader is a drop-in replacement, and Phase 3
/// can flip the default and delete the Swift-string payload.
final class BuiltInSkillsDirectoryParityTests: XCTestCase {

    // MARK: - Loader smoke

    func testDirectoryLoaderReturnsAllShippedSkills() {
        let directoryTemplates = BuiltInSkillsDirectoryLoader.loadAll()
        let swiftStringNames = Set(BuiltInSkills.all.map(\.name))
        let directoryNames = Set(directoryTemplates.map(\.name))
        XCTAssertEqual(
            directoryNames, swiftStringNames,
            "Directory loader should produce the same set of skills as the Swift-string templates"
        )
    }

    // MARK: - Per-skill parity

    func testDeepResearchParity() {
        assertParity(forSkillNamed: "Deep Research")
    }

    func testFileOpsParity() {
        assertParity(forSkillNamed: "File Ops")
    }

    func testHealthPlusParity() {
        assertParity(forSkillNamed: "Health Plus")
    }

    // MARK: - Feature flag dispatch

    func testFlagOffSelectsSwiftStringPath() {
        let originalFlag = BuiltInSkills.loadFromDirectory
        defer { BuiltInSkills.loadFromDirectory = originalFlag }
        BuiltInSkills.loadFromDirectory = false

        let resolved = BuiltInSkills.allResolvedTemplates()
        let expected = BuiltInSkills.all.map { $0.resolved() }
        XCTAssertEqual(resolved.count, expected.count)
        for (got, want) in zip(resolved, expected) {
            assertResolvedTemplatesMatch(got, want, label: got.name)
        }
    }

    func testFlagOnSelectsDirectoryPath() {
        let originalFlag = BuiltInSkills.loadFromDirectory
        defer { BuiltInSkills.loadFromDirectory = originalFlag }
        BuiltInSkills.loadFromDirectory = true

        let resolved = BuiltInSkills.allResolvedTemplates()
        // Same set of skills, regardless of which path was used.
        let names = Set(resolved.map(\.name))
        let expected = Set(BuiltInSkills.all.map(\.name))
        XCTAssertEqual(names, expected)
    }

    func testFlagOnFallsBackOnMissingDirectoryPackage() {
        // Even with the flag on, a slug whose package fails to parse must
        // still surface the legacy Swift-string template — `ensureBuiltInSkills`
        // can never lose a built-in. The directory loader achieves this by
        // returning nil for unparseable packages and `allResolvedTemplates()`
        // falling back to `template.resolved()`.
        let originalFlag = BuiltInSkills.loadFromDirectory
        defer { BuiltInSkills.loadFromDirectory = originalFlag }
        BuiltInSkills.loadFromDirectory = true

        let resolved = BuiltInSkills.allResolvedTemplates()
        XCTAssertEqual(resolved.count, BuiltInSkills.all.count)
    }

    // MARK: - Helpers

    private func assertParity(forSkillNamed name: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let template = BuiltInSkills.all.first(where: { $0.name == name }) else {
            XCTFail("No Swift-string template named \(name)", file: file, line: line)
            return
        }
        let slug = SkillPackage.derivedSlug(forName: name)
        guard let dirTemplate = BuiltInSkillsDirectoryLoader.load(slug: slug, fallbackName: name) else {
            XCTFail("Directory loader returned nil for slug \(slug)", file: file, line: line)
            return
        }
        let stringTemplate = template.resolved()
        assertResolvedTemplatesMatch(dirTemplate, stringTemplate, label: name, file: file, line: line)
    }

    private func assertResolvedTemplatesMatch(
        _ got: BuiltInSkills.ResolvedTemplate,
        _ want: BuiltInSkills.ResolvedTemplate,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(got.name, want.name, "[\(label)] name", file: file, line: line)
        XCTAssertEqual(got.displayName, want.displayName, "[\(label)] displayName", file: file, line: line)
        XCTAssertEqual(got.summary, want.summary, "[\(label)] summary", file: file, line: line)
        XCTAssertEqual(got.content, want.content, "[\(label)] content", file: file, line: line)
        XCTAssertEqual(got.tags, want.tags, "[\(label)] tags", file: file, line: line)
        XCTAssertEqual(got.configSchema, want.configSchema, "[\(label)] configSchema", file: file, line: line)

        // Order can differ between the two sources (the directory loader
        // sorts alphabetically by filename). Compare as sets-by-name and
        // independently per-tool.
        assertScriptsMatch(got.scripts, want.scripts, label: label, file: file, line: line)
        assertToolsMatch(got.customTools, want.customTools, label: label, file: file, line: line)
    }

    private func assertScriptsMatch(
        _ got: [SkillScript],
        _ want: [SkillScript],
        label: String,
        file: StaticString,
        line: UInt
    ) {
        let gotByName = Dictionary(uniqueKeysWithValues: got.map { ($0.name, $0) })
        let wantByName = Dictionary(uniqueKeysWithValues: want.map { ($0.name, $0) })
        XCTAssertEqual(
            Set(gotByName.keys), Set(wantByName.keys),
            "[\(label)] script name set mismatch", file: file, line: line
        )
        for (name, w) in wantByName {
            guard let g = gotByName[name] else { continue }
            XCTAssertEqual(g.language, w.language, "[\(label)] script.\(name).language", file: file, line: line)
            XCTAssertEqual(
                g.code.trimmingCharacters(in: .whitespacesAndNewlines),
                w.code.trimmingCharacters(in: .whitespacesAndNewlines),
                "[\(label)] script.\(name).code", file: file, line: line
            )
            XCTAssertEqual(g.description, w.description, "[\(label)] script.\(name).description", file: file, line: line)
        }
    }

    private func assertToolsMatch(
        _ got: [SkillToolDefinition],
        _ want: [SkillToolDefinition],
        label: String,
        file: StaticString,
        line: UInt
    ) {
        let gotByName = Dictionary(uniqueKeysWithValues: got.map { ($0.name, $0) })
        let wantByName = Dictionary(uniqueKeysWithValues: want.map { ($0.name, $0) })
        XCTAssertEqual(
            Set(gotByName.keys), Set(wantByName.keys),
            "[\(label)] tool name set mismatch", file: file, line: line
        )
        for (name, w) in wantByName {
            guard let g = gotByName[name] else { continue }
            XCTAssertEqual(g.description, w.description, "[\(label)] tool.\(name).description", file: file, line: line)
            XCTAssertEqual(
                g.implementation.trimmingCharacters(in: .whitespacesAndNewlines),
                w.implementation.trimmingCharacters(in: .whitespacesAndNewlines),
                "[\(label)] tool.\(name).implementation", file: file, line: line
            )
            assertParametersMatch(g.parameters, w.parameters, label: "\(label).tool.\(name)", file: file, line: line)
        }
    }

    private func assertParametersMatch(
        _ got: [SkillToolParam],
        _ want: [SkillToolParam],
        label: String,
        file: StaticString,
        line: UInt
    ) {
        let gotByName = Dictionary(uniqueKeysWithValues: got.map { ($0.name, $0) })
        let wantByName = Dictionary(uniqueKeysWithValues: want.map { ($0.name, $0) })
        XCTAssertEqual(
            Set(gotByName.keys), Set(wantByName.keys),
            "[\(label)] param name set mismatch", file: file, line: line
        )
        for (name, w) in wantByName {
            guard let g = gotByName[name] else { continue }
            XCTAssertEqual(g.type, w.type, "[\(label).param.\(name)].type", file: file, line: line)
            XCTAssertEqual(g.required, w.required, "[\(label).param.\(name)].required", file: file, line: line)
            XCTAssertEqual(g.description, w.description, "[\(label).param.\(name)].description", file: file, line: line)
            XCTAssertEqual(g.enumValues, w.enumValues, "[\(label).param.\(name)].enumValues", file: file, line: line)
        }
    }
}
