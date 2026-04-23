import XCTest
@testable import iClaw

final class BuiltInSkillsTests: XCTestCase {

    // MARK: - Template Registry

    func testBuiltInSkillsNotEmpty() {
        XCTAssertFalse(BuiltInSkills.all.isEmpty)
    }

    func testAllSkillsHaveUniqueNames() {
        let names = BuiltInSkills.all.map(\.name)
        XCTAssertEqual(names.count, Set(names).count, "Built-in skill names must be unique")
    }

    func testAllSkillsHaveUniqueLocalizationKeys() {
        let keys = BuiltInSkills.all.map(\.localizationKey)
        XCTAssertEqual(keys.count, Set(keys).count, "Built-in skill localization keys must be unique")
    }

    func testAllSkillsHaveNonEmptyContent() {
        for template in BuiltInSkills.all {
            let resolved = template.resolved()
            XCTAssertFalse(resolved.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "Skill '\(template.name)' must have non-empty content")
        }
    }

    func testAllSkillsHaveNonEmptySummary() {
        for template in BuiltInSkills.all {
            let resolved = template.resolved()
            XCTAssertFalse(resolved.summary.isEmpty,
                           "Skill '\(template.name)' must have a summary")
        }
    }

    func testAllSkillsHaveNonEmptyDisplayName() {
        for template in BuiltInSkills.all {
            let resolved = template.resolved()
            XCTAssertFalse(resolved.displayName.isEmpty,
                           "Skill '\(template.name)' must have a localized display name")
        }
    }

    func testAllSkillsHaveTags() {
        for template in BuiltInSkills.all {
            XCTAssertFalse(template.tags.isEmpty,
                           "Skill '\(template.name)' must have at least one tag")
        }
    }

    /// Built-in templates must ship real capabilities (scripts or custom tools).
    /// Pure-prose templates like the earlier "Code Review" / "Daily Planner" /
    /// "Creative Writer" were removed because the model can improvise that guidance
    /// on its own, and carrying them as built-ins only inflated the library UI.
    func testAllSkillsShipExecutableCapabilities() {
        for template in BuiltInSkills.all {
            let hasCapability = !template.scripts.isEmpty || !template.customTools.isEmpty
            XCTAssertTrue(hasCapability,
                           "Built-in skill '\(template.name)' must ship scripts or custom tools, not just prose")
        }
    }

    func testExpectedBuiltInSkillsRegistered() {
        let names = Set(BuiltInSkills.all.map(\.name))
        XCTAssertEqual(names, Set(["Deep Research", "File Ops", "Health Plus"]),
                        "Unexpected set of built-in skills; update this test intentionally when the list changes")
    }

    func testRemovedSkillsNoLongerRegistered() {
        let names = Set(BuiltInSkills.all.map(\.name))
        XCTAssertFalse(names.contains("Code Review"))
        XCTAssertFalse(names.contains("Daily Planner"))
        XCTAssertFalse(names.contains("Creative Writer"))
    }

    func testResolvedTemplatesHaveNonEmptyToolDescriptions() {
        for template in BuiltInSkills.all {
            let resolved = template.resolved()
            for tool in resolved.customTools {
                XCTAssertFalse(tool.description.isEmpty,
                               "Tool '\(tool.name)' on skill '\(template.name)' must have a localized description")
            }
        }
    }

    // MARK: - Deep Research: Structure

    private var deepResearch: BuiltInSkills.Template {
        BuiltInSkills.all.first(where: { $0.name == "Deep Research" })!
    }

    private var deepResearchResolved: BuiltInSkills.ResolvedTemplate {
        deepResearch.resolved()
    }

    func testDeepResearchSkillExists() {
        XCTAssertNotNil(BuiltInSkills.all.first(where: { $0.name == "Deep Research" }))
    }

    func testDeepResearchLocalizationKey() {
        XCTAssertEqual(deepResearch.localizationKey, "deep_research")
    }

    func testDeepResearchHasTwoScripts() {
        XCTAssertEqual(deepResearch.scripts.count, 2)
    }

    func testDeepResearchHasOneCustomTool() {
        XCTAssertEqual(deepResearch.customTools.count, 1)
    }

    func testDeepResearchTags() {
        let tags = deepResearch.tags
        XCTAssertTrue(tags.contains("research"))
        XCTAssertTrue(tags.contains("analysis"))
    }

    // MARK: - Deep Research: Content / Methodology

    func testDeepResearchContentMentionsBrowserTools() {
        let content = deepResearchResolved.content
        XCTAssertTrue(content.contains("browser_navigate"),
                       "Methodology should guide using browser_navigate")
        XCTAssertTrue(content.contains("browser_get_page_info"),
                       "Methodology should guide using browser_get_page_info")
        XCTAssertTrue(content.contains("browser_extract"),
                       "Methodology should guide using browser_extract")
    }

    func testDeepResearchContentHasToolPreferenceOrder() {
        let content = deepResearchResolved.content
        // Tool identifiers are kept in English across translations; the body
        // surrounding them may differ, but this ordering check uses the
        // identifiers themselves so it's locale-agnostic.
        guard let browserRange = content.range(of: "browser_navigate"),
              let fetchRange = content.range(of: "fetch_and_extract") else {
            XCTFail("Content must mention both browser_navigate and fetch_and_extract")
            return
        }
        XCTAssertTrue(browserRange.lowerBound < fetchRange.lowerBound,
                       "Browser tools should be listed before fetch_and_extract in preference order")
    }

    // MARK: - Deep Research: extract_links Script

    private var extractLinksScript: BuiltInSkills.ScriptTemplate {
        deepResearch.scripts.first(where: { $0.name == "extract_links" })!
    }

    func testExtractLinksScriptExists() {
        XCTAssertNotNil(deepResearch.scripts.first(where: { $0.name == "extract_links" }))
    }

    func testExtractLinksIsJavaScript() {
        XCTAssertEqual(extractLinksScript.language, "javascript")
    }

    func testExtractLinksHandlesDoubleQuotes() {
        // The regex character class ["'] must include double quote
        XCTAssertTrue(extractLinksScript.code.contains(#"["']"#),
                       "extract_links regex must handle double-quoted href attributes")
    }

    func testExtractLinksHandlesSingleQuotes() {
        // The regex character class ["'] must include single quote
        let code = extractLinksScript.code
        XCTAssertTrue(code.contains("[\"']"),
                       "extract_links regex must handle single-quoted href attributes")
    }

    func testExtractLinksDeduplicates() {
        XCTAssertTrue(extractLinksScript.code.contains("findIndex"),
                       "extract_links should deduplicate URLs")
    }

    func testExtractLinksFiltersEmptyText() {
        XCTAssertTrue(extractLinksScript.code.contains("text.length > 0"),
                       "extract_links should filter out links with empty text")
    }

    func testExtractLinksFiltersNonHTTP() {
        XCTAssertTrue(extractLinksScript.code.contains("startsWith('http')"),
                       "extract_links should filter non-HTTP URLs")
    }

    func testExtractLinksHasLocalizedDescription() {
        let resolvedScript = deepResearchResolved.scripts.first(where: { $0.name == "extract_links" })
        XCTAssertNotNil(resolvedScript?.description)
        XCTAssertFalse(resolvedScript?.description?.isEmpty ?? true)
    }

    // MARK: - Deep Research: summarize_text Script

    private var summarizeTextScript: BuiltInSkills.ScriptTemplate {
        deepResearch.scripts.first(where: { $0.name == "summarize_text" })!
    }

    func testSummarizeTextScriptExists() {
        XCTAssertNotNil(deepResearch.scripts.first(where: { $0.name == "summarize_text" }))
    }

    func testSummarizeTextIsJavaScript() {
        XCTAssertEqual(summarizeTextScript.language, "javascript")
    }

    func testSummarizeTextUsesPositionScoring() {
        let code = summarizeTextScript.code
        // Position-based scoring: earlier sentences get higher score
        XCTAssertTrue(code.contains("1 / (i + 1)"),
                       "summarize_text should use position-based importance scoring")
    }

    func testSummarizeTextUsesLengthScoring() {
        let code = summarizeTextScript.code
        XCTAssertTrue(code.contains("s.length / 200"),
                       "summarize_text should factor in sentence length")
    }

    func testSummarizeTextPreservesOriginalOrder() {
        let code = summarizeTextScript.code
        // After selecting top sentences by score, restore reading order
        XCTAssertTrue(code.contains("findIndex"),
                       "summarize_text should restore original sentence order after ranking")
    }

    func testSummarizeTextHandlesEmptyInput() {
        let code = summarizeTextScript.code
        XCTAssertTrue(code.contains("sentences.length === 0"),
                       "summarize_text should handle texts with no extractable sentences")
    }

    func testSummarizeTextHasLocalizedDescription() {
        let resolvedScript = deepResearchResolved.scripts.first(where: { $0.name == "summarize_text" })
        XCTAssertNotNil(resolvedScript?.description)
        XCTAssertFalse(resolvedScript?.description?.isEmpty ?? true)
    }

    // MARK: - Deep Research: fetch_and_extract Tool

    private var fetchAndExtractTool: BuiltInSkills.ToolTemplate {
        deepResearch.customTools.first(where: { $0.name == "fetch_and_extract" })!
    }

    private var fetchAndExtractResolved: SkillToolDefinition {
        deepResearchResolved.customTools.first(where: { $0.name == "fetch_and_extract" })!
    }

    func testFetchAndExtractToolExists() {
        XCTAssertNotNil(deepResearch.customTools.first(where: { $0.name == "fetch_and_extract" }))
    }

    func testFetchAndExtractHasURLParam() {
        let urlParam = fetchAndExtractTool.parameters.first(where: { $0.name == "url" })
        XCTAssertNotNil(urlParam)
        XCTAssertEqual(urlParam?.type, "string")
    }

    func testFetchAndExtractHasMaxLengthParam() {
        let param = fetchAndExtractTool.parameters.first(where: { $0.name == "max_length" })
        XCTAssertNotNil(param)
        XCTAssertEqual(param?.type, "number")
        XCTAssertEqual(param?.required, false, "max_length should be optional")
    }

    func testFetchAndExtractResolvedDescriptionMentionsFallback() {
        XCTAssertTrue(fetchAndExtractResolved.description.contains("browser_navigate"),
                       "Tool description should mention browser tools as fallback")
    }

    func testFetchAndExtractErrorMessageSuggestsBrowserFallback() {
        let impl = fetchAndExtractTool.implementation
        // Both error paths should suggest browser_navigate as alternative
        let browserMentions = impl.components(separatedBy: "browser_navigate").count - 1
        XCTAssertGreaterThanOrEqual(browserMentions, 2,
                       "Both HTTP error and network error paths should suggest browser_navigate")
    }

    func testFetchAndExtractStripsNavigation() {
        let impl = fetchAndExtractTool.implementation
        // Should strip nav, header, footer for cleaner text
        XCTAssertTrue(impl.contains("<nav"), "Should strip <nav> elements")
        XCTAssertTrue(impl.contains("<header"), "Should strip <header> elements")
        XCTAssertTrue(impl.contains("<footer"), "Should strip <footer> elements")
    }

    func testFetchAndExtractDecodesHTMLEntities() {
        let impl = fetchAndExtractTool.implementation
        XCTAssertTrue(impl.contains("&nbsp;"))
        XCTAssertTrue(impl.contains("&amp;"))
        XCTAssertTrue(impl.contains("&lt;"))
        XCTAssertTrue(impl.contains("&gt;"))
        XCTAssertTrue(impl.contains("&quot;"))
        XCTAssertTrue(impl.contains("&#39;"))
    }

    func testFetchAndExtractDefaultMaxLength() {
        XCTAssertTrue(fetchAndExtractTool.implementation.contains("5000"),
                       "Default max_length should be 5000")
    }

    // MARK: - File Ops: Structure

    private var fileOps: BuiltInSkills.Template {
        BuiltInSkills.all.first(where: { $0.name == "File Ops" })!
    }

    private var fileOpsResolved: BuiltInSkills.ResolvedTemplate {
        fileOps.resolved()
    }

    func testFileOpsSkillExists() {
        XCTAssertNotNil(BuiltInSkills.all.first(where: { $0.name == "File Ops" }))
    }

    func testFileOpsLocalizationKey() {
        XCTAssertEqual(fileOps.localizationKey, "file_ops")
    }

    func testFileOpsHasExpectedCustomTools() {
        let names = Set(fileOps.customTools.map(\.name))
        XCTAssertEqual(names, Set(["cp", "mv", "stat", "mkdir", "tree", "touch", "exists"]))
    }

    func testFileOpsToolsHaveNonEmptyImplementations() {
        for tool in fileOps.customTools {
            XCTAssertFalse(tool.implementation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "File Ops tool '\(tool.name)' must have a non-empty implementation")
        }
    }

    func testFileOpsImplementationsUseFsNamespace() {
        for tool in fileOps.customTools {
            XCTAssertTrue(tool.implementation.contains("fs."),
                           "File Ops tool '\(tool.name)' should delegate to the fs namespace")
        }
    }

    func testFileOpsCpHasRequiredParams() {
        let cp = fileOps.customTools.first(where: { $0.name == "cp" })!
        let required = Set(cp.parameters.filter { $0.required }.map(\.name))
        XCTAssertEqual(required, Set(["src", "dest"]))
    }

    func testFileOpsMvHasRequiredParams() {
        let mv = fileOps.customTools.first(where: { $0.name == "mv" })!
        let required = Set(mv.parameters.filter { $0.required }.map(\.name))
        XCTAssertEqual(required, Set(["src", "dest"]))
    }

    func testFileOpsContentMentionsFdOps() {
        let content = fileOpsResolved.content
        XCTAssertTrue(content.contains("fs.open"),
                       "File Ops skill should document POSIX fd operations")
        XCTAssertTrue(content.contains("fs.seek"),
                       "File Ops skill should document the seek operation")
    }

    func testFileOpsTags() {
        let tags = Set(fileOps.tags)
        XCTAssertTrue(tags.contains("files"))
    }

    // MARK: - Health Plus: Structure

    private var healthPlus: BuiltInSkills.Template {
        BuiltInSkills.all.first(where: { $0.name == "Health Plus" })!
    }

    private var healthPlusResolved: BuiltInSkills.ResolvedTemplate {
        healthPlus.resolved()
    }

    func testHealthPlusSkillExists() {
        XCTAssertNotNil(BuiltInSkills.all.first(where: { $0.name == "Health Plus" }))
    }

    func testHealthPlusLocalizationKey() {
        XCTAssertEqual(healthPlus.localizationKey, "health_plus")
    }

    func testHealthPlusHasExpectedCustomTools() {
        let names = Set(healthPlus.customTools.map(\.name))
        XCTAssertEqual(names, Set([
            "read_blood_pressure", "read_blood_glucose", "read_blood_oxygen", "read_body_temperature",
            "write_blood_pressure", "write_blood_glucose", "write_blood_oxygen", "write_body_temperature",
            "write_body_fat", "write_height", "write_heart_rate",
            "write_dietary_carbohydrates", "write_dietary_protein", "write_dietary_fat",
            "write_workout",
        ]))
    }

    func testHealthPlusCustomToolCount() {
        XCTAssertEqual(healthPlus.customTools.count, 15)
    }

    func testHealthPlusToolsHaveNonEmptyImplementations() {
        for tool in healthPlus.customTools {
            XCTAssertFalse(tool.implementation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "Health Plus tool '\(tool.name)' must have a non-empty implementation")
        }
    }

    func testHealthPlusImplementationsUseAppleHealthNamespace() {
        for tool in healthPlus.customTools {
            XCTAssertTrue(tool.implementation.contains("apple.health."),
                           "Health Plus tool '\(tool.name)' should delegate to the apple.health namespace")
        }
    }

    func testHealthPlusWriteBloodPressureRequiredParams() {
        let tool = healthPlus.customTools.first(where: { $0.name == "write_blood_pressure" })!
        let required = Set(tool.parameters.filter { $0.required }.map(\.name))
        XCTAssertEqual(required, Set(["systolic", "diastolic"]))
    }

    func testHealthPlusWriteWorkoutRequiredParams() {
        let tool = healthPlus.customTools.first(where: { $0.name == "write_workout" })!
        let required = Set(tool.parameters.filter { $0.required }.map(\.name))
        XCTAssertEqual(required, Set(["start_date", "end_date"]))
    }

    func testHealthPlusContentMentionsAppleHealth() {
        XCTAssertTrue(healthPlusResolved.content.contains("apple.health."),
                       "Health Plus skill should document the apple.health namespace")
    }

    func testHealthPlusTags() {
        let tags = Set(healthPlus.tags)
        XCTAssertTrue(tags.contains("health"))
    }
}
