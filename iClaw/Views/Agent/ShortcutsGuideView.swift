import SwiftUI

/// Guide view explaining how to set up Apple Shortcuts to trigger cron jobs reliably.
struct ShortcutsGuideView: View {
    let cronJob: CronJob?

    @Environment(\.dismiss) private var dismiss

    private var triggerURL: String {
        if let job = cronJob {
            return "iclaw://cron/trigger/\(job.id.uuidString)"
        }
        return "iclaw://cron/trigger/{JOB_ID}"
    }

    private var runAllURL: String {
        "iclaw://cron/run-due"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    whySection
                    setupSteps
                    urlReferenceSection
                    tipsSection
                }
                .padding()
            }
            .navigationTitle("Shortcuts 指引")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "shortcuts")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("使用 Shortcuts 辅助触发定时任务")
                        .font(.headline)
                    Text("确保 Cron Job 在后台也能可靠执行")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var whySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("为什么需要 Shortcuts？", systemImage: "questionmark.circle")
                .font(.headline)

            Text("iOS 对后台任务有严格限制。系统可能延迟或跳过 BGAppRefreshTask，导致定时任务无法准时触发。通过 Apple Shortcuts 的「自动化」功能，可以在指定时间自动打开 iClaw 的 URL Scheme，确保任务准时执行。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    @ViewBuilder
    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("设置步骤", systemImage: "list.number")
                .font(.headline)

            StepView(number: 1, title: "打开 Shortcuts App", detail: "前往「快捷指令」App，选择底部「自动化」标签页。")

            StepView(number: 2, title: "创建个人自动化", detail: "点击右上角「+」→「创建个人自动化」→ 选择「特定时间」。")

            StepView(number: 3, title: "设置触发时间", detail: "根据你的 Cron Job 调度设置对应的时间和重复规则（每天/工作日/特定日期）。")

            StepView(number: 4, title: "添加动作", detail: "搜索并添加「打开URL」动作，填入以下 URL：")

            HStack {
                Text(triggerURL)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.blue)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    UIPasteboard.general.string = triggerURL
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
            )

            StepView(number: 5, title: "关闭「运行前询问」", detail: "确保关闭「运行前询问」开关，这样自动化才能在后台静默执行。")

            StepView(number: 6, title: "完成", detail: "点击「完成」保存自动化。现在你的 Cron Job 会通过 Shortcuts 在指定时间可靠触发。")
        }
    }

    private var urlReferenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("URL 参考", systemImage: "link")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                URLRefRow(
                    label: "触发特定任务",
                    url: triggerURL,
                    description: "触发指定 ID 的 Cron Job"
                )

                URLRefRow(
                    label: "执行所有到期任务",
                    url: runAllURL,
                    description: "检查并执行所有到期的 Cron Job"
                )
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("提示", systemImage: "lightbulb")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                tipRow("对于高频任务（如每小时），建议同时保留 App 内定时和 Shortcuts 双重保障。")
                tipRow("Shortcuts 自动化在设备锁屏时也能执行，但需要设备有网络连接。")
                tipRow("如果有多个 Cron Job，可以使用「执行所有到期任务」URL 统一触发。")
                tipRow("首次使用 URL Scheme 时，系统可能会弹出确认对话框，确认后后续调用将静默执行。")
            }
        }
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Helper Views

private struct StepView: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct URLRefRow: View {
    let label: String
    let url: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
            HStack {
                Text(url)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.blue)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    UIPasteboard.general.string = url
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Text(description)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
