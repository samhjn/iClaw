import Foundation
import SwiftData

struct ModelTools {
    let agent: Agent
    let modelContext: ModelContext

    func setModel(arguments: [String: Any]) -> String {
        guard let role = arguments["role"] as? String else {
            return "[Error] Missing required parameter: role"
        }

        let router = ModelRouter(modelContext: modelContext)
        let allProviders = router.fetchAllProviders()

        switch role {
        case "primary":
            guard let modelId = arguments["model_id"] as? String,
                  let uuid = UUID(uuidString: modelId) else {
                return "[Error] Missing or invalid model_id"
            }
            guard allProviders.contains(where: { $0.id == uuid }) else {
                return "[Error] No provider found with id: \(modelId)"
            }
            let modelName = arguments["model_name"] as? String
            agent.primaryProviderId = uuid
            agent.primaryModelNameOverride = modelName
            agent.updatedAt = Date()
            try? modelContext.save()

            let p = router.providerById(uuid)
            let effectiveModel = modelName ?? p?.modelName ?? ""
            return "Primary model set to: \(p?.name ?? modelId) (\(effectiveModel))"

        case "fallback":
            guard let modelIds = arguments["model_ids"] as? [String] else {
                return "[Error] Missing model_ids array for fallback role"
            }
            let uuids = modelIds.compactMap { UUID(uuidString: $0) }
            let valid = uuids.filter { uid in allProviders.contains(where: { $0.id == uid }) }
            agent.fallbackProviderIds = valid
            agent.updatedAt = Date()
            try? modelContext.save()

            let names = valid.compactMap { uid in router.providerById(uid) }
                .map { "\($0.name) (\($0.modelName))" }
            return "Fallback chain set to: \(names.joined(separator: " → "))"

        case "add_fallback":
            guard let modelId = arguments["model_id"] as? String,
                  let uuid = UUID(uuidString: modelId) else {
                return "[Error] Missing or invalid model_id"
            }
            guard allProviders.contains(where: { $0.id == uuid }) else {
                return "[Error] No provider found with id: \(modelId)"
            }
            var current = agent.fallbackProviderIds
            if !current.contains(uuid) {
                current.append(uuid)
                agent.fallbackProviderIds = current
                agent.updatedAt = Date()
                try? modelContext.save()
            }
            let p = router.providerById(uuid)
            return "Added \(p?.name ?? modelId) (\(p?.modelName ?? "")) to fallback chain (position \(current.count))"

        case "sub_agent":
            let modelId = arguments["model_id"] as? String
            let modelName = arguments["model_name"] as? String
            if let modelId, let uuid = UUID(uuidString: modelId) {
                guard allProviders.contains(where: { $0.id == uuid }) else {
                    return "[Error] No provider found with id: \(modelId)"
                }
                agent.subAgentProviderId = uuid
                agent.subAgentModelNameOverride = modelName
                agent.updatedAt = Date()
                try? modelContext.save()
                let p = router.providerById(uuid)
                let effectiveModel = modelName ?? p?.modelName ?? ""
                return "Sub-agent default model set to: \(p?.name ?? modelId) (\(effectiveModel))"
            } else {
                agent.subAgentProviderId = nil
                agent.subAgentModelNameOverride = nil
                agent.updatedAt = Date()
                try? modelContext.save()
                return "Sub-agent model cleared — sub-agents will inherit parent's primary model"
            }

        default:
            return "[Error] Invalid role '\(role)'. Use: primary, fallback, add_fallback, sub_agent"
        }
    }

    func getModel(arguments: [String: Any]) -> String {
        let router = ModelRouter(modelContext: modelContext)
        let chain = router.resolveProviderChain(for: agent)

        var lines: [String] = ["## Model Configuration for \(agent.name)"]

        if let pid = agent.primaryProviderId, let p = router.providerById(pid) {
            lines.append("- **Primary**: \(p.name) (`\(p.modelName)`) [id: \(p.id.uuidString)]")
        } else {
            lines.append("- **Primary**: (global default)")
        }

        if !agent.fallbackProviderIds.isEmpty {
            let fbNames = agent.fallbackProviderIds.enumerated().compactMap { (i, uid) -> String? in
                guard let p = router.providerById(uid) else { return nil }
                return "  \(i + 1). \(p.name) (`\(p.modelName)`) [id: \(p.id.uuidString)]"
            }
            lines.append("- **Fallback chain**:")
            lines.append(contentsOf: fbNames)
        } else {
            lines.append("- **Fallback chain**: (none)")
        }

        if let sid = agent.subAgentProviderId, let p = router.providerById(sid) {
            lines.append("- **Sub-agent default**: \(p.name) (`\(p.modelName)`) [id: \(p.id.uuidString)]")
        } else {
            lines.append("- **Sub-agent default**: (inherits from primary)")
        }

        lines.append("")
        lines.append("Effective resolution order: \(chain.map { "\($0.name)(\($0.modelName))" }.joined(separator: " → "))")

        return lines.joined(separator: "\n")
    }

    func listModels(arguments: [String: Any]) -> String {
        let router = ModelRouter(modelContext: modelContext)
        let providers = router.fetchAllProviders()

        if providers.isEmpty {
            return "No LLM providers configured. Add one in Settings."
        }

        let totalModels = providers.reduce(0) { $0 + $1.enabledModels.count }
        var lines: [String] = ["## Available Models (\(totalModels) models across \(providers.count) providers)"]
        for p in providers {
            let defaultTag = p.isDefault ? " ⭐ default" : ""
            lines.append("### \(p.name)\(defaultTag)")
            lines.append("  Endpoint: \(p.endpoint)")
            lines.append("  Provider ID: `\(p.id.uuidString)`")
            for model in p.enabledModels {
                let isDefault = model == p.modelName ? " (default)" : ""
                let caps = p.capabilities(for: model)
                var tags: [String] = []
                if caps.supportsVision { tags.append("vision") }
                if caps.supportsToolUse { tags.append("tool_use") }
                if caps.supportsImageGeneration { tags.append("image_gen") }
                if caps.supportsReasoning { tags.append("reasoning") }
                let capsStr = tags.isEmpty ? "none" : tags.joined(separator: ", ")
                lines.append("  - `\(model)`\(isDefault) — capabilities: \(capsStr)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
