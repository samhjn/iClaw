import Foundation

// swiftlint:disable type_body_length file_length

/// Centralized localization keys. All user-facing strings should be referenced
/// through this enum to guarantee compile-time safety and a single source of truth.
enum L10n {

    private static func tr(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private static func tr(_ key: String, _ args: CVarArg...) -> String {
        String(format: NSLocalizedString(key, comment: ""), arguments: args)
    }

    // MARK: - Tabs

    enum Tabs {
        static var sessions: String { tr("tabs.sessions") }
        static var agents: String { tr("tabs.agents") }
        static var browser: String { tr("tabs.browser") }
        static var skills: String { tr("tabs.skills") }
        static var settings: String { tr("tabs.settings") }
    }

    // MARK: - Common

    enum Common {
        static var save: String { tr("common.save") }
        static var cancel: String { tr("common.cancel") }
        static var delete: String { tr("common.delete") }
        static var create: String { tr("common.create") }
        static var edit: String { tr("common.edit") }
        static var done: String { tr("common.done") }
        static var copy: String { tr("common.copy") }
        static var copied: String { tr("common.copied") }
        static var dismiss: String { tr("common.dismiss") }
        static var enable: String { tr("common.enable") }
        static var disable: String { tr("common.disable") }
        static var defaultLabel: String { tr("common.default") }
        static var active: String { tr("common.active") }
        static var preview: String { tr("common.preview") }
        static var empty: String { tr("common.empty") }
        static var refresh: String { tr("common.refresh") }
        static var add: String { tr("common.add") }
        static var name: String { tr("common.name") }
        static var unknown: String { tr("common.unknown") }
    }

    // MARK: - Chat

    enum Chat {
        static var messagePlaceholder: String { tr("chat.messagePlaceholder") }
        static var cancelling: String { tr("chat.cancelling") }
        static var thinking: String { tr("chat.thinking") }
        static var compressingContext: String { tr("chat.compressingContext") }
        static var renameSession: String { tr("chat.renameSession") }
        static var rename: String { tr("chat.rename") }
        static var compressContext: String { tr("chat.compressContext") }
        static var title: String { tr("chat.title") }
        static var openLink: String { tr("chat.openLink") }
        static var share: String { tr("chat.share") }
        static var loadingImage: String { tr("chat.loadingImage") }
        static var imageLoadFailed: String { tr("chat.imageLoadFailed") }
        static var newChat: String { tr("chat.newChat") }
        static var aborted: String { tr("chat.aborted") }
        static var toolCallAborted: String { tr("chat.toolCallAborted") }
        static var noAgent: String { tr("chat.noAgent") }
        static var noCompressModel: String { tr("chat.noCompressModel") }
        static func sessionBlocked(_ title: String) -> String { tr("chat.sessionBlocked", title) }
        static func compressionInfo(active: String, threshold: String, total: Int, compressed: Int) -> String {
            tr("chat.compressionInfo", active, threshold, total, compressed)
        }
        static func tokenUsage(active: String, threshold: String) -> String {
            tr("chat.tokenUsage", active, threshold)
        }
        static func messageStats(total: Int, compressed: Int) -> String {
            tr("chat.messageStats", total, compressed)
        }
        static func pendingCompression(_ count: Int) -> String {
            tr("chat.pendingCompression", count)
        }
        static func compressedBadge(_ count: Int) -> String {
            tr("chat.compressedBadge", count)
        }
        static var cancelStuckReason: String { tr("chat.cancelStuckReason") }
        static var forceStoppedContent: String { tr("chat.forceStoppedContent") }
        static var deleteSessionTitle: String { tr("chat.deleteSessionTitle") }
        static var deleteSessionMessage: String { tr("chat.deleteSessionMessage") }
        static var deleteAgentTitle: String { tr("chat.deleteAgentTitle") }
        static func deleteAgentMessage(_ name: String) -> String { tr("chat.deleteAgentMessage", name) }
        static var thinkingProcess: String { tr("chat.thinkingProcess") }
        static var addImage: String { tr("chat.addImage") }
        static var photoLibrary: String { tr("chat.photoLibrary") }
        static var camera: String { tr("chat.camera") }
        static var pasteFromClipboard: String { tr("chat.pasteFromClipboard") }
        static var imagePlaceholder: String { tr("chat.imagePlaceholder") }
        static var saveImageToPhotos: String { tr("chat.saveImageToPhotos") }
        static var imageSaved: String { tr("chat.imageSaved") }
        static var copyImage: String { tr("chat.copyImage") }
        static func modalityStripped(_ count: Int, _ model: String) -> String { tr("chat.modalityStripped", count, model) }
    }

    // MARK: - Agents

    enum Agents {
        static var title: String { tr("agents.title") }
        static var newAgent: String { tr("agents.newAgent") }
        static var agentName: String { tr("agents.agentName") }
        static var createAgent: String { tr("agents.createAgent") }
        static var noAgents: String { tr("agents.noAgents") }
        static var createAgentDescription: String { tr("agents.createAgentDescription") }
        static var enterName: String { tr("agents.enterName") }
    }

    // MARK: - Agent Detail

    enum AgentDetail {
        static var config: String { tr("agentDetail.config") }
        static var modelConfig: String { tr("agentDetail.modelConfig") }
        static var skills: String { tr("agentDetail.skills") }
        static var cronJobs: String { tr("agentDetail.cronJobs") }
        static var customConfigs: String { tr("agentDetail.customConfigs") }
        static var subAgents: String { tr("agentDetail.subAgents") }
        static var codeSnippets: String { tr("agentDetail.codeSnippets") }
        static var newConfig: String { tr("agentDetail.newConfig") }
        static var keyPlaceholder: String { tr("agentDetail.keyPlaceholder") }
        static var noSubAgents: String { tr("agentDetail.noSubAgents") }
        static var subAgentsDescription: String { tr("agentDetail.subAgentsDescription") }
        static func sessionsCount(_ count: Int) -> String { tr("agentDetail.sessionsCount", count) }
        static func msgsCount(_ count: Int) -> String { tr("agentDetail.msgsCount", count) }
        static func subAgentsTitle(_ count: Int) -> String { tr("agentDetail.subAgentsTitle", count) }
        static var noCodeSnippets: String { tr("agentDetail.noCodeSnippets") }
        static var codeSnippetsDescription: String { tr("agentDetail.codeSnippetsDescription") }
        static var snippetInfo: String { tr("agentDetail.snippetInfo") }
        static var snippetName: String { tr("agentDetail.snippetName") }
        static var snippetLanguage: String { tr("agentDetail.snippetLanguage") }
        static var snippetCode: String { tr("agentDetail.snippetCode") }
        static var newSnippet: String { tr("agentDetail.newSnippet") }
    }

    // MARK: - Model Config

    enum ModelConfig {
        static var title: String { tr("modelConfig.title") }
        static var globalDefault: String { tr("modelConfig.globalDefault") }
        static var primaryModel: String { tr("modelConfig.primaryModel") }
        static var primaryModelFooter: String { tr("modelConfig.primaryModelFooter") }
        static var noFallback: String { tr("modelConfig.noFallback") }
        static var addFallback: String { tr("modelConfig.addFallback") }
        static var fallbackChain: String { tr("modelConfig.fallbackChain") }
        static var fallbackFooter: String { tr("modelConfig.fallbackFooter") }
        static var inheritFromPrimary: String { tr("modelConfig.inheritFromPrimary") }
        static var subAgentModel: String { tr("modelConfig.subAgentModel") }
        static var subAgentDefault: String { tr("modelConfig.subAgentDefault") }
        static var subAgentFooter: String { tr("modelConfig.subAgentFooter") }
        static var compressionThreshold: String { tr("modelConfig.compressionThreshold") }
        static func defaultThreshold(_ value: Int) -> String { tr("modelConfig.defaultThreshold", value) }
        static var systemDefault: String { tr("modelConfig.systemDefault") }
        static var resetDefault: String { tr("modelConfig.resetDefault") }
        static var contextCompression: String { tr("modelConfig.contextCompression") }
        static var compressionFooter: String { tr("modelConfig.compressionFooter") }
        static var noModels: String { tr("modelConfig.noModels") }
        static var override: String { tr("modelConfig.override") }
        static var primary: String { tr("modelConfig.primary") }
        static var fallback: String { tr("modelConfig.fallback") }
        static var subAgent: String { tr("modelConfig.subAgent") }
        static var resolutionOrder: String { tr("modelConfig.resolutionOrder") }
        static var resolutionFooter: String { tr("modelConfig.resolutionFooter") }
    }

    // MARK: - Cron Jobs

    enum CronJobs {
        static var title: String { tr("cronJobs.title") }
        static var noCronJobs: String { tr("cronJobs.noCronJobs") }
        static var noCronJobsDescription: String { tr("cronJobs.noCronJobsDescription") }
        static var shortcutsTrigger: String { tr("cronJobs.shortcutsTrigger") }
        static var shortcutsDescription: String { tr("cronJobs.shortcutsDescription") }
        static func runsCount(_ count: Int) -> String { tr("cronJobs.runsCount", count) }
        static var nextPrefix: String { tr("cronJobs.nextPrefix") }
        static var jobInfo: String { tr("cronJobs.jobInfo") }
        static var schedule: String { tr("cronJobs.schedule") }
        static var description: String { tr("cronJobs.description") }
        static var enabled: String { tr("cronJobs.enabled") }
        static var jobHint: String { tr("cronJobs.jobHint") }
        static var statistics: String { tr("cronJobs.statistics") }
        static var totalRuns: String { tr("cronJobs.totalRuns") }
        static var lastRun: String { tr("cronJobs.lastRun") }
        static var ago: String { tr("cronJobs.ago") }
        static var nextRun: String { tr("cronJobs.nextRun") }
        static var created: String { tr("cronJobs.created") }
        static var triggerURL: String { tr("cronJobs.triggerURL") }
        static var viewShortcutsGuide: String { tr("cronJobs.viewShortcutsGuide") }
        static var shortcutsIntegration: String { tr("cronJobs.shortcutsIntegration") }
        static var shortcutsIntegrationFooter: String { tr("cronJobs.shortcutsIntegrationFooter") }
        static var lastSession: String { tr("cronJobs.lastSession") }
        static var editJob: String { tr("cronJobs.editJob") }
        static var newCronJob: String { tr("cronJobs.newCronJob") }
        static var basic: String { tr("cronJobs.basic") }
        static var jobName: String { tr("cronJobs.jobName") }
        static var cronExpression: String { tr("cronJobs.cronExpression") }
        static var nextFire: String { tr("cronJobs.nextFire") }
        static var cronFormat: String { tr("cronJobs.cronFormat") }
        static var quickPresets: String { tr("cronJobs.quickPresets") }
        static var everyHour: String { tr("cronJobs.everyHour") }
        static var daily9am: String { tr("cronJobs.daily9am") }
        static var weekdays9am: String { tr("cronJobs.weekdays9am") }
        static var weeklyMon: String { tr("cronJobs.weeklyMon") }
        static var every30min: String { tr("cronJobs.every30min") }
        static var monthly1st: String { tr("cronJobs.monthly1st") }
        static var jobHintFooter: String { tr("cronJobs.jobHintFooter") }
    }

    // MARK: - Shortcuts Guide

    enum Shortcuts {
        static var title: String { tr("shortcuts.title") }
        static var headerTitle: String { tr("shortcuts.headerTitle") }
        static var headerSubtitle: String { tr("shortcuts.headerSubtitle") }
        static var whyNeeded: String { tr("shortcuts.whyNeeded") }
        static var whyDescription: String { tr("shortcuts.whyDescription") }
        static var setupSteps: String { tr("shortcuts.setupSteps") }
        static var step1Title: String { tr("shortcuts.step1Title") }
        static var step1Detail: String { tr("shortcuts.step1Detail") }
        static var step2Title: String { tr("shortcuts.step2Title") }
        static var step2Detail: String { tr("shortcuts.step2Detail") }
        static var step3Title: String { tr("shortcuts.step3Title") }
        static var step3Detail: String { tr("shortcuts.step3Detail") }
        static var step4Title: String { tr("shortcuts.step4Title") }
        static var step4Detail: String { tr("shortcuts.step4Detail") }
        static var step5Title: String { tr("shortcuts.step5Title") }
        static var step5Detail: String { tr("shortcuts.step5Detail") }
        static var step6Title: String { tr("shortcuts.step6Title") }
        static var step6Detail: String { tr("shortcuts.step6Detail") }
        static var urlReference: String { tr("shortcuts.urlReference") }
        static var triggerSpecific: String { tr("shortcuts.triggerSpecific") }
        static var triggerSpecificDesc: String { tr("shortcuts.triggerSpecificDesc") }
        static var runAllDue: String { tr("shortcuts.runAllDue") }
        static var runAllDueDesc: String { tr("shortcuts.runAllDueDesc") }
        static var tips: String { tr("shortcuts.tips") }
        static var tip1: String { tr("shortcuts.tip1") }
        static var tip2: String { tr("shortcuts.tip2") }
        static var tip3: String { tr("shortcuts.tip3") }
        static var tip4: String { tr("shortcuts.tip4") }
    }

    // MARK: - Sessions

    enum Sessions {
        static var title: String { tr("sessions.title") }
        static var noSessions: String { tr("sessions.noSessions") }
        static var noSessionsDescription: String { tr("sessions.noSessionsDescription") }
        static var newSession: String { tr("sessions.newSession") }
        static var noAgents: String { tr("sessions.noAgents") }
        static var noAgentsDescription: String { tr("sessions.noAgentsDescription") }
        static func sessionsCount(_ count: Int) -> String { tr("sessions.sessionsCount", count) }
        static var selectAgent: String { tr("sessions.selectAgent") }
        static func messagesCount(_ count: Int) -> String { tr("sessions.messagesCount", count) }
    }

    // MARK: - Settings

    enum Settings {
        static var title: String { tr("settings.title") }
        static var llmProviders: String { tr("settings.llmProviders") }
        static var addProvider: String { tr("settings.addProvider") }
        static var about: String { tr("settings.about") }
        static var version: String { tr("settings.version") }
    }

    // MARK: - LLM Provider

    enum Provider {
        static var editProvider: String { tr("provider.editProvider") }
        static var addProvider: String { tr("provider.addProvider") }
        static var addModel: String { tr("provider.addModel") }
        static var modelNamePlaceholder: String { tr("provider.modelNamePlaceholder") }
        static var provider: String { tr("provider.provider") }
        static var endpoint: String { tr("provider.endpoint") }
        static var authentication: String { tr("provider.authentication") }
        static var apiKey: String { tr("provider.apiKey") }
        static var defaultModel: String { tr("provider.defaultModel") }
        static var defaultModelFooter: String { tr("provider.defaultModelFooter") }
        static var noModelsEnabled: String { tr("provider.noModelsEnabled") }
        static var setDefault: String { tr("provider.setDefault") }
        static var manuallyAddModel: String { tr("provider.manuallyAddModel") }
        static var enabledModels: String { tr("provider.enabledModels") }
        static var enabledModelsFooter: String { tr("provider.enabledModelsFooter") }
        static var fetchFromAPI: String { tr("provider.fetchFromAPI") }
        static func availableToEnable(_ count: Int) -> String { tr("provider.availableToEnable", count) }
        static func allModelsEnabled(_ count: Int) -> String { tr("provider.allModelsEnabled", count) }
        static var enableAll: String { tr("provider.enableAll") }
        static var remoteModels: String { tr("provider.remoteModels") }
        static var remoteModelsFooter: String { tr("provider.remoteModelsFooter") }
        static func maxTokens(_ value: Int) -> String { tr("provider.maxTokens", value) }
        static var parameters: String { tr("provider.parameters") }
        static var supportsVision: String { tr("provider.supportsVision") }
        static var supportsVisionFooter: String { tr("provider.supportsVisionFooter") }
        static var supportsToolUse: String { tr("provider.supportsToolUse") }
        static var supportsToolUseFooter: String { tr("provider.supportsToolUseFooter") }
        static var supportsImageGeneration: String { tr("provider.supportsImageGeneration") }
        static var supportsImageGenerationFooter: String { tr("provider.supportsImageGenerationFooter") }
        static var supportsReasoning: String { tr("provider.supportsReasoning") }
        static var supportsReasoningFooter: String { tr("provider.supportsReasoningFooter") }
        static var apiStyle: String { tr("provider.apiStyle") }
        static var apiStyleFooter: String { tr("provider.apiStyleFooter") }
        static var modelCapabilities: String { tr("provider.modelCapabilities") }
        static var presets: String { tr("provider.presets") }
    }

    // MARK: - Skills

    enum Skills {
        static var title: String { tr("skills.title") }
        static var noSkills: String { tr("skills.noSkills") }
        static var noSkillsDescription: String { tr("skills.noSkillsDescription") }
        static var createSkill: String { tr("skills.createSkill") }
        static var customSkills: String { tr("skills.customSkills") }
        static var builtInSkills: String { tr("skills.builtInSkills") }
        static var builtIn: String { tr("skills.builtIn") }
        static var searchSkills: String { tr("skills.searchSkills") }
        static var deleteSkill: String { tr("skills.deleteSkill") }
        static func deleteSkillMessage(_ name: String) -> String { tr("skills.deleteSkillMessage", name) }
        static var content: String { tr("skills.content") }
        static var noAgents: String { tr("skills.noAgents") }
        static var noAgentsDescription: String { tr("skills.noAgentsDescription") }
        static func install(_ name: String) -> String { tr("skills.install", name) }
        static func skillsActive(_ count: Int) -> String { tr("skills.skillsActive", count) }
        static var agents: String { tr("skills.agents") }
        static var editSkill: String { tr("skills.editSkill") }
        static var newSkill: String { tr("skills.newSkill") }
        static var info: String { tr("skills.info") }
        static var skillName: String { tr("skills.skillName") }
        static var summary: String { tr("skills.summary") }
        static var tags: String { tr("skills.tags") }
        static var contentMarkdown: String { tr("skills.contentMarkdown") }
        static var contentFooter: String { tr("skills.contentFooter") }
        static var noSkillsInstalled: String { tr("skills.noSkillsInstalled") }
        static var installDescription: String { tr("skills.installDescription") }
        static var browseLibrary: String { tr("skills.browseLibrary") }
        static var uninstall: String { tr("skills.uninstall") }
        static var skillLibrary: String { tr("skills.skillLibrary") }
        static func activeInstalled(active: Int, installed: Int) -> String {
            tr("skills.activeInstalled", active, installed)
        }
    }

    // MARK: - Cron Parser

    enum CronDesc {
        static var invalidExpression: String { tr("cron.invalidExpression") }
        static var everyMinute: String { tr("cron.everyMinute") }
        static func atMinute(_ m: Int) -> String { tr("cron.atMinute", m) }
        static func atMinutes(_ s: String) -> String { tr("cron.atMinutes", s) }
        static var ofEveryHour: String { tr("cron.ofEveryHour") }
        static func ofHour(_ h: Int) -> String { tr("cron.ofHour", h) }
        static func ofHours(_ s: String) -> String { tr("cron.ofHours", s) }
        static func onDays(_ s: String) -> String { tr("cron.onDays", s) }
        static func inMonths(_ s: String) -> String { tr("cron.inMonths", s) }
        static func onWeekdays(_ s: String) -> String { tr("cron.onWeekdays", s) }
        static var weekdayNames: [String] {
            [tr("cron.sun"), tr("cron.mon"), tr("cron.tue"), tr("cron.wed"),
             tr("cron.thu"), tr("cron.fri"), tr("cron.sat")]
        }
    }

    // MARK: - Cron Executor

    enum CronExec {
        static var completed: String { tr("cronExec.completed") }
        static func completedBody(_ name: String) -> String { tr("cronExec.completedBody", name) }
        static var noProvider: String { tr("cronExec.noProvider") }
    }

    // MARK: - Chat Errors

    enum ChatError {
        static var noProvider: String { tr("chatError.noProvider") }
        static var noAgent: String { tr("chatError.noAgent") }
    }

    // MARK: - Browser

    enum Browser {
        static var title: String { tr("browser.title") }
        static var urlPlaceholder: String { tr("browser.urlPlaceholder") }
        static func agentControlling(_ name: String) -> String { tr("browser.agentControlling", name) }
        static var takeOver: String { tr("browser.takeOver") }
        static var takeOverTitle: String { tr("browser.takeOverTitle") }
        static func takeOverMessage(_ name: String) -> String { tr("browser.takeOverMessage", name) }
        static var closePage: String { tr("browser.closePage") }
        static var closePageTitle: String { tr("browser.closePageTitle") }
        static var closePageMessage: String { tr("browser.closePageMessage") }
    }

    // MARK: - Markdown Editor

    enum MarkdownEditor {
        static var preview: String { tr("markdownEditor.preview") }
        static var edit: String { tr("markdownEditor.edit") }
    }

    // MARK: - Tool Card Display Names

    enum ToolCard {
        static var javascript: String { tr("toolCard.javascript") }
        static var readConfig: String { tr("toolCard.readConfig") }
        static var writeConfig: String { tr("toolCard.writeConfig") }
        static var saveCode: String { tr("toolCard.saveCode") }
        static var loadCode: String { tr("toolCard.loadCode") }
        static var listCode: String { tr("toolCard.listCode") }
        static var createAgent: String { tr("toolCard.createAgent") }
        static var messageAgent: String { tr("toolCard.messageAgent") }
        static var collectOutput: String { tr("toolCard.collectOutput") }
        static var listAgents: String { tr("toolCard.listAgents") }
        static var stopAgent: String { tr("toolCard.stopAgent") }
        static var deleteAgent: String { tr("toolCard.deleteAgent") }
        static var scheduleJob: String { tr("toolCard.scheduleJob") }
        static var removeJob: String { tr("toolCard.removeJob") }
        static var listJobs: String { tr("toolCard.listJobs") }
        static var createSkill: String { tr("toolCard.createSkill") }
        static var deleteSkill: String { tr("toolCard.deleteSkill") }
        static var installSkill: String { tr("toolCard.installSkill") }
        static var uninstallSkill: String { tr("toolCard.uninstallSkill") }
        static var listSkills: String { tr("toolCard.listSkills") }
        static var readSkill: String { tr("toolCard.readSkill") }
        static var setModel: String { tr("toolCard.setModel") }
        static var getModel: String { tr("toolCard.getModel") }
        static var listModels: String { tr("toolCard.listModels") }
        static var browse: String { tr("toolCard.browse") }
        static var pageInfo: String { tr("toolCard.pageInfo") }
        static var click: String { tr("toolCard.click") }
        static var input: String { tr("toolCard.input") }
        static var select: String { tr("toolCard.select") }
        static var extract: String { tr("toolCard.extract") }
        static var browserJS: String { tr("toolCard.browserJS") }
        static var waitElement: String { tr("toolCard.waitElement") }
        static var scroll: String { tr("toolCard.scroll") }
        static var runSnippet: String { tr("toolCard.runSnippet") }
        static var deleteCode: String { tr("toolCard.deleteCode") }
    }
}

// swiftlint:enable type_body_length file_length
