import SwiftUI
import SwiftData

struct CronJobListView: View {
    let agent: Agent
    @Environment(\.modelContext) private var modelContext
    @State private var showAddSheet = false
    @State private var showShortcutsGuide = false

    var body: some View {
        List {
            if agent.cronJobs.isEmpty {
                ContentUnavailableView(
                    "No Cron Jobs",
                    systemImage: "clock.badge",
                    description: Text("Schedule recurring jobs from here or ask your AI agent to create one.")
                )
            } else {
                ForEach(sortedJobs, id: \.id) { job in
                    NavigationLink {
                        CronJobDetailView(job: job)
                    } label: {
                        CronJobRowView(job: job)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            modelContext.delete(job)
                            try? modelContext.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            job.isEnabled.toggle()
                            job.updatedAt = Date()
                            if job.isEnabled {
                                job.nextRunAt = try? CronParser.nextFireDate(after: Date(), for: job.cronExpression)
                            }
                            try? modelContext.save()
                        } label: {
                            Label(
                                job.isEnabled ? "Disable" : "Enable",
                                systemImage: job.isEnabled ? "pause" : "play"
                            )
                        }
                        .tint(job.isEnabled ? .orange : .green)
                    }
                }

                Section {
                    Button {
                        showShortcutsGuide = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Shortcuts 辅助触发")
                                    .font(.subheadline)
                                Text("使用 Apple Shortcuts 确保任务可靠执行")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "shortcuts")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Cron Jobs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            CronJobEditView(agent: agent)
        }
        .sheet(isPresented: $showShortcutsGuide) {
            ShortcutsGuideView(cronJob: nil)
        }
    }

    private var sortedJobs: [CronJob] {
        agent.cronJobs.sorted { ($0.nextRunAt ?? .distantFuture) < ($1.nextRunAt ?? .distantFuture) }
    }
}

// MARK: - Row

struct CronJobRowView: View {
    let job: CronJob

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(job.isEnabled ? .green : .gray)
                    .frame(width: 8, height: 8)
                Text(job.name)
                    .font(.headline)
                Spacer()
                Text(job.cronExpression)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.secondary.opacity(0.15)))
            }

            Text(CronParser.describe(job.cronExpression))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                if let next = job.nextRunAt, job.isEnabled {
                    Label(next, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                Label("\(job.runCount) runs", systemImage: "arrow.clockwise")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(job.jobHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

private extension Label where Title == Text, Icon == Image {
    init(_ date: Date, style: Text.DateStyle) {
        self.init {
            Text("Next: ") + Text(date, style: style)
        } icon: {
            Image(systemName: "clock")
        }
    }
}

// MARK: - Detail

struct CronJobDetailView: View {
    @Bindable var job: CronJob
    @Environment(\.modelContext) private var modelContext
    @State private var showShortcutsGuide = false

    private var triggerURL: String {
        "iclaw://cron/trigger/\(job.id.uuidString)"
    }

    var body: some View {
        Form {
            Section("Job Info") {
                LabeledContent("Name", value: job.name)
                LabeledContent("Schedule", value: job.cronExpression)
                LabeledContent("Description", value: CronParser.describe(job.cronExpression))
                Toggle("Enabled", isOn: $job.isEnabled)
                    .onChange(of: job.isEnabled) { _, enabled in
                        if enabled {
                            job.nextRunAt = try? CronParser.nextFireDate(after: Date(), for: job.cronExpression)
                        }
                        job.updatedAt = Date()
                        try? modelContext.save()
                    }
            }

            Section("Job Hint") {
                Text(job.jobHint)
                    .font(.body)
            }

            Section("Statistics") {
                LabeledContent("Total Runs", value: "\(job.runCount)")
                if let last = job.lastRunAt {
                    LabeledContent("Last Run") {
                        Text(last, style: .relative) + Text(" ago")
                    }
                }
                if let next = job.nextRunAt, job.isEnabled {
                    LabeledContent("Next Run") {
                        Text(next, style: .relative)
                    }
                }
                LabeledContent("Created") {
                    Text(job.createdAt, style: .date)
                }
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("触发 URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(triggerURL)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.blue)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = triggerURL
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    showShortcutsGuide = true
                } label: {
                    Label("查看 Shortcuts 设置指引", systemImage: "shortcuts")
                }
            } header: {
                Text("Shortcuts 集成")
            } footer: {
                Text("通过 Apple Shortcuts 的「自动化」功能，使用此 URL 确保定时任务可靠触发。")
            }

            if let sessionId = job.lastSessionId {
                Section("Last Session") {
                    Text("Session ID: \(sessionId.uuidString)")
                        .font(.caption)
                        .fontDesign(.monospaced)
                }
            }
        }
        .navigationTitle(job.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShortcutsGuide) {
            ShortcutsGuideView(cronJob: job)
        }
    }
}

// MARK: - Create / Edit

struct CronJobEditView: View {
    let agent: Agent
    var existingJob: CronJob?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var cronExpression = "0 9 * * *"
    @State private var jobHint = ""
    @State private var isEnabled = true
    @State private var validationError: String?
    @State private var showShortcutsGuide = false
    @State private var savedJob: CronJob?

    private var isEditing: Bool { existingJob != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Job Name", text: $name)
                    Toggle("Enabled", isOn: $isEnabled)
                }

                Section {
                    TextField("Cron Expression", text: $cronExpression)
                        .fontDesign(.monospaced)
                        .autocapitalization(.none)
                        .onChange(of: cronExpression) { _, _ in validate() }

                    if let error = validationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text(CronParser.describe(cronExpression))
                            .font(.caption)
                            .foregroundStyle(.green)

                        if let next = try? CronParser.nextFireDate(after: Date(), for: cronExpression) {
                            HStack {
                                Text("Next fire:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(next, style: .date)
                                    .font(.caption)
                                Text(next, style: .time)
                                    .font(.caption)
                            }
                        }
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("Format: minute hour day-of-month month day-of-week\nPresets: @hourly @daily @weekly @monthly @yearly")
                }

                Section("Quick Presets") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            presetButton("Every hour", "0 * * * *")
                            presetButton("Daily 9am", "0 9 * * *")
                            presetButton("Weekdays 9am", "0 9 * * 1-5")
                            presetButton("Weekly Mon", "0 9 * * 1")
                            presetButton("Every 30min", "*/30 * * * *")
                            presetButton("Monthly 1st", "0 0 1 * *")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section {
                    TextEditor(text: $jobHint)
                        .frame(minHeight: 120)
                } header: {
                    Text("Job Hint")
                } footer: {
                    Text("This prompt will be sent to the LLM each time the job triggers.")
                }
            }
            .navigationTitle(isEditing ? "Edit Job" : "New Cron Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        if !isEditing {
                            showShortcutsGuide = true
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty || jobHint.isEmpty || validationError != nil)
                }
            }
            .onAppear {
                if let job = existingJob {
                    name = job.name
                    cronExpression = job.cronExpression
                    jobHint = job.jobHint
                    isEnabled = job.isEnabled
                }
                validate()
            }
            .sheet(isPresented: $showShortcutsGuide, onDismiss: { dismiss() }) {
                ShortcutsGuideView(cronJob: savedJob)
            }
        }
    }

    private func presetButton(_ label: String, _ expr: String) -> some View {
        Button {
            cronExpression = expr
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(cronExpression == expr ? Color.accentColor : Color(.systemGray5))
                )
                .foregroundStyle(cronExpression == expr ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func validate() {
        validationError = CronParser.validate(cronExpression)
    }

    private func save() {
        if let job = existingJob {
            job.name = name
            job.cronExpression = cronExpression
            job.jobHint = jobHint
            job.isEnabled = isEnabled
            job.nextRunAt = try? CronParser.nextFireDate(after: Date(), for: cronExpression)
            job.updatedAt = Date()
            savedJob = job
        } else {
            let job = CronJob(
                name: name,
                cronExpression: cronExpression,
                jobHint: jobHint,
                agent: agent,
                isEnabled: isEnabled
            )
            job.nextRunAt = try? CronParser.nextFireDate(after: Date(), for: cronExpression)
            modelContext.insert(job)
            savedJob = job
        }
        try? modelContext.save()
    }
}
