import SwiftUI
import SwiftData
import UIKit

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
                if !skill.scripts.isEmpty {
                    Divider()
                    scriptsSection
                }
                if !skill.customTools.isEmpty {
                    Divider()
                    toolsSection
                }
            }
            .padding()
        }
        .navigationTitle(skill.effectiveDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showInstallSheet = true } label: {
                    Image(systemName: "cpu.fill")
                }
                if !skill.isBuiltIn {
                    Menu {
                        Button { isEditing = true } label: {
                            Label(L10n.Common.edit, systemImage: "pencil")
                        }
                        if hasOnDiskPackage {
                            Button { revealInFiles() } label: {
                                Label(L10n.Skills.revealInFiles, systemImage: "folder")
                            }
                        }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label(L10n.Common.delete, systemImage: "trash")
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
        .alert(L10n.Skills.deleteSkill, isPresented: $showDeleteConfirm) {
            Button(L10n.Common.delete, role: .destructive) {
                SkillService(modelContext: modelContext).deleteSkill(skill)
                onDelete?()
                dismiss()
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.Skills.deleteSkillMessage(skill.effectiveDisplayName))
        }
    }

    /// True for user skills whose package directory exists under
    /// `<Documents>/Skills/<slug>/`. Built-ins are bundle-backed and not
    /// reachable through the iOS Files app.
    private var hasOnDiskPackage: Bool {
        guard !skill.isBuiltIn else { return false }
        let slug = SkillPackage.derivedSlug(forName: skill.name)
        let url = AgentFileManager.shared.skillsRoot.appendingPathComponent(slug, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Open the iOS Files app at this skill's package directory using the
    /// `shareddocuments://` URL scheme. The app's `UIFileSharingEnabled`
    /// flag in Info.plist makes the path resolvable from outside.
    private func revealInFiles() {
        let slug = SkillPackage.derivedSlug(forName: skill.name)
        let path = AgentFileManager.shared.skillsRoot
            .appendingPathComponent(slug, isDirectory: true).path
        guard let url = URL(string: "shareddocuments://" + path) else { return }
        UIApplication.shared.open(url)
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
            Label("\(skill.installCount) \(L10n.Skills.agents)", systemImage: "cpu")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Skills.content)
                .font(.headline)

            Text(skill.content)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var scriptsSection: some View {
        if !skill.scripts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.Skills.scriptsCount(skill.scripts.count), systemImage: "terminal")
                    .font(.headline)

                ForEach(skill.scripts, id: \.name) { script in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(script.name)
                                .font(.subheadline.bold())
                            Spacer()
                            Text(script.language)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.15)))
                        }
                        if let desc = script.description {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(script.code)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var toolsSection: some View {
        if !skill.customTools.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.Skills.customToolsCount(skill.customTools.count), systemImage: "wrench.and.screwdriver")
                    .font(.headline)

                ForEach(skill.customTools, id: \.name) { tool in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tool.name)
                            .font(.subheadline.bold())
                        Text(tool.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !tool.parameters.isEmpty {
                            HStack(spacing: 4) {
                                Text("\(L10n.Skills.parameters):")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                ForEach(tool.parameters, id: \.name) { param in
                                    Text("\(param.name):\(param.type)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                                }
                            }
                        }

                        Text(tool.implementation)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
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
                    ContentUnavailableView(L10n.Skills.noAgents, systemImage: "cpu", description: Text(L10n.Skills.noAgentsDescription))
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
                                    Text(L10n.Skills.skillsActive(count))
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
            .navigationTitle(L10n.Skills.install(skill.effectiveDisplayName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.done) { dismiss() }
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
    @State private var scripts: [SkillScript] = []
    @State private var customTools: [SkillToolDefinition] = []

    // Editing state for new script
    @State private var showAddScript = false
    @State private var newScriptName = ""
    @State private var newScriptDesc = ""
    @State private var newScriptCode = ""

    // Editing state for new tool
    @State private var showAddTool = false
    @State private var newToolName = ""
    @State private var newToolDesc = ""
    @State private var newToolCode = ""
    @State private var newToolParams: [SkillToolParam] = []

    init(existingSkill: Skill? = nil, onSave: (() -> Void)? = nil) {
        self.existingSkill = existingSkill
        self.onSave = onSave
    }

    private var isEditing: Bool { existingSkill != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.Skills.info) {
                    TextField(L10n.Skills.skillName, text: $name)
                    TextField(L10n.Skills.summary, text: $summary)
                    TextField(L10n.Skills.tags, text: $tagsText)
                        .autocapitalization(.none)
                }

                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 200)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text(L10n.Skills.contentMarkdown)
                } footer: {
                    Text(L10n.Skills.contentFooter)
                }

                // Scripts section
                Section {
                    ForEach(Array(scripts.enumerated()), id: \.element.name) { index, script in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(script.name).font(.subheadline.bold())
                                Spacer()
                                Button(role: .destructive) {
                                    scripts.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                            }
                            if let desc = script.description, !desc.isEmpty {
                                Text(desc).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(script.code)
                                .font(.system(.caption2, design: .monospaced))
                                .lineLimit(3)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        newScriptName = ""
                        newScriptDesc = ""
                        newScriptCode = ""
                        showAddScript = true
                    } label: {
                        Label(L10n.Skills.addScript, systemImage: "plus")
                    }
                } header: {
                    Label(L10n.Skills.scripts, systemImage: "terminal")
                } footer: {
                    Text(L10n.Skills.scriptsFooter)
                }

                // Custom Tools section
                Section {
                    ForEach(Array(customTools.enumerated()), id: \.element.name) { index, tool in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(tool.name).font(.subheadline.bold())
                                Spacer()
                                Button(role: .destructive) {
                                    customTools.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                            }
                            Text(tool.description).font(.caption).foregroundStyle(.secondary)
                            if !tool.parameters.isEmpty {
                                Text("Params: \(tool.parameters.map { $0.name }.joined(separator: ", "))")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Button {
                        newToolName = ""
                        newToolDesc = ""
                        newToolCode = ""
                        newToolParams = []
                        showAddTool = true
                    } label: {
                        Label(L10n.Skills.addTool, systemImage: "plus")
                    }
                } header: {
                    Label(L10n.Skills.customTools, systemImage: "wrench.and.screwdriver")
                } footer: {
                    Text(L10n.Skills.customToolsFooter)
                }
            }
            .navigationTitle(isEditing ? L10n.Skills.editSkill : L10n.Skills.newSkill)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save) {
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
                    scripts = s.scripts
                    customTools = s.customTools
                }
            }
            .sheet(isPresented: $showAddScript) {
                addScriptSheet
            }
            .sheet(isPresented: $showAddTool) {
                addToolSheet
            }
        }
    }

    // MARK: - Add Script Sheet

    private var addScriptSheet: some View {
        NavigationStack {
            Form {
                Section(L10n.Skills.info) {
                    TextField(L10n.Skills.scriptName, text: $newScriptName)
                        .autocapitalization(.none)
                    TextField(L10n.Skills.descriptionOptional, text: $newScriptDesc)
                }
                Section(L10n.Skills.jsCode) {
                    TextEditor(text: $newScriptCode)
                        .frame(minHeight: 200)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .navigationTitle(L10n.Skills.addScript)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { showAddScript = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let script = SkillScript(
                            name: newScriptName,
                            code: newScriptCode,
                            description: newScriptDesc.isEmpty ? nil : newScriptDesc
                        )
                        scripts.append(script)
                        showAddScript = false
                    }
                    .disabled(newScriptName.isEmpty || newScriptCode.isEmpty)
                }
            }
        }
    }

    // MARK: - Add Tool Sheet

    private var addToolSheet: some View {
        NavigationStack {
            Form {
                Section(L10n.Skills.toolInfo) {
                    TextField(L10n.Skills.toolName, text: $newToolName)
                        .autocapitalization(.none)
                    TextField(L10n.Skills.description, text: $newToolDesc)
                }
                Section {
                    ForEach(Array(newToolParams.enumerated()), id: \.offset) { index, _ in
                        HStack {
                            TextField("Name", text: Binding(
                                get: { newToolParams[index].name },
                                set: { newToolParams[index] = SkillToolParam(name: $0, type: newToolParams[index].type, description: newToolParams[index].description, required: newToolParams[index].required) }
                            ))
                            .autocapitalization(.none)
                            .frame(maxWidth: 100)
                            Picker("", selection: Binding(
                                get: { newToolParams[index].type },
                                set: { newToolParams[index] = SkillToolParam(name: newToolParams[index].name, type: $0, description: newToolParams[index].description, required: newToolParams[index].required) }
                            )) {
                                Text("string").tag("string")
                                Text("number").tag("number")
                                Text("boolean").tag("boolean")
                            }
                            .labelsHidden()
                            .frame(maxWidth: 90)
                            Button(role: .destructive) {
                                newToolParams.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                        }
                    }
                    Button {
                        newToolParams.append(SkillToolParam(name: "", description: ""))
                    } label: {
                        Label(L10n.Skills.addParameter, systemImage: "plus")
                    }
                } header: {
                    Text(L10n.Skills.parameters)
                }
                Section {
                    TextEditor(text: $newToolCode)
                        .frame(minHeight: 200)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text(L10n.Skills.jsImplementation)
                } footer: {
                    Text(L10n.Skills.jsImplementationFooter)
                }
            }
            .navigationTitle(L10n.Skills.addTool)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { showAddTool = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let validParams = newToolParams.filter { !$0.name.isEmpty }
                        let tool = SkillToolDefinition(
                            name: newToolName,
                            description: newToolDesc,
                            parameters: validParams,
                            implementation: newToolCode
                        )
                        customTools.append(tool)
                        showAddTool = false
                    }
                    .disabled(newToolName.isEmpty || newToolCode.isEmpty)
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        let tags = tagsText.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        if let s = existingSkill {
            let service = SkillService(modelContext: modelContext)
            service.updateSkill(s, name: name, summary: summary, content: content, tags: tags)
            s.scripts = scripts
            s.customTools = customTools
            try? modelContext.save()
        } else {
            let service = SkillService(modelContext: modelContext)
            _ = service.createSkill(
                name: name, summary: summary, content: content, tags: tags,
                scripts: scripts, customTools: customTools
            )
        }
        onSave?()
    }
}
