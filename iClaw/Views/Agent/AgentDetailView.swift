import SwiftUI

struct AgentDetailView: View {
    @Bindable var agent: Agent
    let viewModel: AgentViewModel
    @State private var selectedConfig: ConfigType = .soul

    enum ConfigType: String, CaseIterable {
        case soul = "SOUL"
        case memory = "MEMORY"
        case user = "USER"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Config", selection: $selectedConfig) {
                ForEach(ConfigType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            MarkdownEditorView(
                content: bindingForConfig(selectedConfig),
                title: "\(selectedConfig.rawValue).md"
            )
        }
        .navigationTitle(agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    NavigationLink("Model Config") {
                        AgentModelConfigView(agent: agent)
                    }
                    NavigationLink("Skills") {
                        AgentSkillsView(agent: agent)
                    }
                    NavigationLink("Cron Jobs") {
                        CronJobListView(agent: agent)
                    }
                    NavigationLink("Custom Configs") {
                        CustomConfigsView(agent: agent)
                    }
                    NavigationLink("Sub-Agents") {
                        SubAgentListView(parentAgent: agent)
                    }
                    NavigationLink("Code Snippets") {
                        CodeSnippetListView(agent: agent)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onChange(of: agent.soulMarkdown) { _, _ in viewModel.updateAgent(agent) }
        .onChange(of: agent.memoryMarkdown) { _, _ in viewModel.updateAgent(agent) }
        .onChange(of: agent.userMarkdown) { _, _ in viewModel.updateAgent(agent) }
    }

    private func bindingForConfig(_ type: ConfigType) -> Binding<String> {
        switch type {
        case .soul: return $agent.soulMarkdown
        case .memory: return $agent.memoryMarkdown
        case .user: return $agent.userMarkdown
        }
    }
}

struct CustomConfigsView: View {
    let agent: Agent
    @Environment(\.modelContext) private var modelContext
    @State private var showAddSheet = false
    @State private var newKey = ""
    @State private var newContent = ""

    var body: some View {
        List {
            ForEach(agent.customConfigs, id: \.id) { config in
                NavigationLink {
                    MarkdownEditorView(
                        content: Binding(
                            get: { config.content },
                            set: {
                                config.content = $0
                                config.updatedAt = Date()
                                try? modelContext.save()
                            }
                        ),
                        title: config.key
                    )
                } label: {
                    VStack(alignment: .leading) {
                        Text(config.key).font(.headline)
                        Text(config.content.prefix(80))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .navigationTitle("Custom Configs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Config", isPresented: $showAddSheet) {
            TextField("Key (e.g. RULES)", text: $newKey)
            Button("Create") {
                let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty {
                    let config = AgentConfig(key: key, content: "", agent: agent)
                    modelContext.insert(config)
                    try? modelContext.save()
                }
                newKey = ""
            }
            Button("Cancel", role: .cancel) { newKey = "" }
        }
    }
}

struct SubAgentListView: View {
    let parentAgent: Agent

    var body: some View {
        List {
            if parentAgent.subAgents.isEmpty {
                ContentUnavailableView(
                    "No Sub-Agents",
                    systemImage: "cpu",
                    description: Text("Sub-agents are created by the AI during conversations.")
                )
            } else {
                ForEach(parentAgent.subAgents, id: \.id) { sub in
                    VStack(alignment: .leading) {
                        Text(sub.name).font(.headline)
                        Text("\(sub.sessions.count) sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Sub-Agents")
    }
}

struct CodeSnippetListView: View {
    let agent: Agent

    var body: some View {
        List {
            if agent.codeSnippets.isEmpty {
                ContentUnavailableView(
                    "No Code Snippets",
                    systemImage: "doc.text",
                    description: Text("Code snippets are saved by the AI agent.")
                )
            } else {
                ForEach(agent.codeSnippets, id: \.id) { snippet in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(snippet.name).font(.headline)
                            Spacer()
                            Text(snippet.language)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.secondary.opacity(0.2)))
                        }
                        Text(snippet.code.prefix(120))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Code Snippets")
    }
}
