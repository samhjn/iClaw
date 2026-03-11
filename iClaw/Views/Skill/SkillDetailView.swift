import SwiftUI
import SwiftData

struct SkillDetailView: View {
    @Bindable var skill: Skill
    let onDelete: (() -> Void)?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var showDeleteConfirm = false
    @State private var showInstallSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                Divider()
                metadataSection
                Divider()
                contentSection
            }
            .padding()
        }
        .navigationTitle(skill.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showInstallSheet = true } label: {
                    Image(systemName: "cpu.fill")
                }
                if !skill.isBuiltIn {
                    Menu {
                        Button { isEditing = true } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            SkillEditView(existingSkill: skill)
        }
        .sheet(isPresented: $showInstallSheet) {
            InstallSkillOnAgentSheet(skill: skill)
        }
        .alert("Delete Skill", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                SkillService(modelContext: modelContext).deleteSkill(skill)
                onDelete?()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete '\(skill.name)' and remove it from all agents.")
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(skill.summary)
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(skill.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
            }
        }
    }

    private var metadataSection: some View {
        HStack(spacing: 20) {
            Label(skill.author, systemImage: "person")
            Label("v\(skill.version)", systemImage: "tag")
            Label("\(skill.installCount) agents", systemImage: "cpu")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content")
                .font(.headline)

            Text(skill.content)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Install on agent sheet

struct InstallSkillOnAgentSheet: View {
    let skill: Skill
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var agents: [Agent] = []

    var body: some View {
        NavigationStack {
            List {
                if agents.isEmpty {
                    ContentUnavailableView("No Agents", systemImage: "cpu", description: Text("Create an agent first."))
                } else {
                    ForEach(agents, id: \.id) { agent in
                        let installed = agent.installedSkills.contains { $0.skill?.id == skill.id }
                        Button {
                            let service = SkillService(modelContext: modelContext)
                            if installed {
                                _ = service.uninstallSkill(skill, from: agent)
                            } else {
                                _ = service.installSkill(skill, on: agent)
                            }
                            loadAgents()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(agent.name).font(.headline)
                                    let count = agent.activeSkills.count
                                    Text("\(count) skill\(count == 1 ? "" : "s") active")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if installed {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            .navigationTitle("Install \(skill.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { loadAgents() }
        }
    }

    private func loadAgents() {
        let descriptor = FetchDescriptor<Agent>(
            predicate: #Predicate { $0.parentAgent == nil },
            sortBy: [SortDescriptor(\.name)]
        )
        agents = (try? modelContext.fetch(descriptor)) ?? []
    }
}

// MARK: - Create / Edit

struct SkillEditView: View {
    var existingSkill: Skill?
    var onSave: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var summary = ""
    @State private var content = ""
    @State private var tagsText = ""

    init(existingSkill: Skill? = nil, onSave: (() -> Void)? = nil) {
        self.existingSkill = existingSkill
        self.onSave = onSave
    }

    private var isEditing: Bool { existingSkill != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Info") {
                    TextField("Skill Name", text: $name)
                    TextField("Summary (one-line description)", text: $summary)
                    TextField("Tags (comma-separated)", text: $tagsText)
                        .autocapitalization(.none)
                }

                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 250)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Content (Markdown)")
                } footer: {
                    Text("Write instructions, methodology, or knowledge that will be injected into the agent's system prompt when this skill is installed.")
                }
            }
            .navigationTitle(isEditing ? "Edit Skill" : "New Skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(name.isEmpty || content.isEmpty)
                }
            }
            .onAppear {
                if let s = existingSkill {
                    name = s.name
                    summary = s.summary
                    content = s.content
                    tagsText = s.tags.joined(separator: ", ")
                }
            }
        }
    }

    private func save() {
        let tags = tagsText.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        if let s = existingSkill {
            let service = SkillService(modelContext: modelContext)
            service.updateSkill(s, name: name, summary: summary, content: content, tags: tags)
        } else {
            let service = SkillService(modelContext: modelContext)
            _ = service.createSkill(name: name, summary: summary, content: content, tags: tags)
        }
        onSave?()
    }
}
