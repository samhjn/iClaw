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
            guard let p = allProviders.first(where: { $0.id == uuid }) else {
                return "[Error] No provider found with id: \(modelId)"
            }
            if p.isMediaOnly {
                return "[Error] Cannot set \(p.name) as primary model — only LLM providers are allowed. Image/video generation providers cannot be used as chat models."
            }
            let modelName = arguments["model_name"] as? String
            let effectiveModel = modelName ?? p.modelName
            if !agent.isModelAllowed(providerId: uuid, modelName: effectiveModel) {
                return "[Error] Model \(p.name) (\(effectiveModel)) is not in the allowed model whitelist"
            }
            agent.primaryProviderId = uuid
            agent.primaryModelNameOverride = modelName
            agent.updatedAt = Date()
            try? modelContext.save()
            return "Primary model set to: \(p.name) (\(effectiveModel))"

        case "fallback":
            guard let modelIds = arguments["model_ids"] as? [String] else {
                return "[Error] Missing model_ids array for fallback role"
            }
            let modelNames = arguments["model_names"] as? [String]
            let uuids = modelIds.compactMap { UUID(uuidString: $0) }
            let valid = uuids.filter { uid in allProviders.contains(where: { $0.id == uid }) }
            var rejected: [String] = []
            var accepted: [UUID] = []
            var acceptedModelNames: [String] = []
            for (i, uid) in valid.enumerated() {
                guard let p = router.providerById(uid) else { continue }
                if p.isMediaOnly {
                    rejected.append("\(p.name) (media-only provider)")
                    continue
                }
                let mn = (modelNames != nil && i < modelNames!.count && !modelNames![i].isEmpty) ? modelNames![i] : nil
                let effectiveModel = mn ?? p.modelName
                if agent.isModelAllowed(providerId: uid, modelName: effectiveModel) {
                    accepted.append(uid)
                    acceptedModelNames.append(mn ?? "")
                } else {
                    rejected.append("\(p.name) (\(effectiveModel))")
                }
            }
            agent.fallbackProviderIds = accepted
            agent.fallbackModelNames = acceptedModelNames
            agent.updatedAt = Date()
            try? modelContext.save()

            let names = accepted.enumerated().compactMap { (i, uid) -> String? in
                guard let p = router.providerById(uid) else { return nil }
                let mn = i < acceptedModelNames.count && !acceptedModelNames[i].isEmpty ? acceptedModelNames[i] : p.modelName
                return "\(p.name) (\(mn))"
            }
            var result = "Fallback chain set to: \(names.joined(separator: " → "))"
            if !rejected.isEmpty {
                result += "\n[Warning] Rejected by whitelist: \(rejected.joined(separator: ", "))"
            }
            return result

        case "add_fallback":
            guard let modelId = arguments["model_id"] as? String,
                  let uuid = UUID(uuidString: modelId) else {
                return "[Error] Missing or invalid model_id"
            }
            guard let p = allProviders.first(where: { $0.id == uuid }) else {
                return "[Error] No provider found with id: \(modelId)"
            }
            if p.isMediaOnly {
                return "[Error] Cannot add \(p.name) as fallback — only LLM providers are allowed. Image/video generation providers cannot be used as chat models."
            }
            let modelName = arguments["model_name"] as? String
            let effectiveModel = modelName ?? p.modelName
            if !agent.isModelAllowed(providerId: uuid, modelName: effectiveModel) {
                return "[Error] Model \(p.name) (\(effectiveModel)) is not in the allowed model whitelist"
            }
            var current = agent.fallbackProviderIds
            if !current.contains(uuid) {
                current.append(uuid)
                agent.fallbackProviderIds = current
                agent.updatedAt = Date()
                try? modelContext.save()
            }
            return "Added \(p.name) (\(effectiveModel)) to fallback chain (position \(current.count))"

        case "sub_agent":
            let modelId = arguments["model_id"] as? String
            let modelName = arguments["model_name"] as? String
            if let modelId, let uuid = UUID(uuidString: modelId) {
                guard let p = allProviders.first(where: { $0.id == uuid }) else {
                    return "[Error] No provider found with id: \(modelId)"
                }
                if p.isMediaOnly {
                    return "[Error] Cannot set \(p.name) as sub-agent model — only LLM providers are allowed. Image/video generation providers cannot be used as chat models."
                }
                let effectiveModel = modelName ?? p.modelName
                if !agent.isModelAllowed(providerId: uuid, modelName: effectiveModel) {
                    return "[Error] Model \(p.name) (\(effectiveModel)) is not in the allowed model whitelist"
                }
                agent.subAgentProviderId = uuid
                agent.subAgentModelNameOverride = modelName
                agent.updatedAt = Date()
                try? modelContext.save()
                return "Sub-agent default model set to: \(p.name) (\(effectiveModel))"
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

        let whitelist = agent.allowedModelIds
        let hasWhitelist = !whitelist.isEmpty

        var lines: [String] = []
        var totalModels = 0
        var providerCount = 0

        for p in providers {
            // Only list LLM providers — image/video generation providers cannot be used as chat models
            guard !p.isMediaOnly else { continue }

            let models: [String]
            if hasWhitelist {
                models = p.enabledModels.filter { model in
                    whitelist.contains("\(p.id.uuidString):\(model)")
                }
                guard !models.isEmpty else { continue }
            } else {
                models = p.enabledModels
            }

            providerCount += 1
            totalModels += models.count

            let defaultTag = p.isDefault ? " ⭐ default" : ""
            lines.append("### \(p.name)\(defaultTag)")
            lines.append("  Endpoint: \(p.endpoint)")
            lines.append("  Provider ID: `\(p.id.uuidString)`")
            for model in models {
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

        let header = hasWhitelist
            ? "## Available Models (\(totalModels) allowed models across \(providerCount) providers, filtered by whitelist)"
            : "## Available Models (\(totalModels) models across \(providerCount) providers)"
        lines.insert(header, at: 0)

        return lines.joined(separator: "\n")
    }
}
