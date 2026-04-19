import SwiftUI

/// Extension-side agent picker. Displays the snapshot published by the main
/// app and lets the user choose which agent should receive the shared files.
struct SharePickerView: View {
    let agents: [AgentSnapshotEntry]
    let onSelect: (AgentSnapshotEntry) -> Void
    let onCancel: () -> Void

    @State private var isStaging = false
    @State private var stagingAgentId: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if agents.isEmpty {
                    emptyState
                } else {
                    agentList
                }
            }
            .navigationTitle("iClaw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isStaging)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No agents yet")
                .font(.headline)
            Text("Open iClaw and create an agent before sharing files.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var agentList: some View {
        List {
            Section {
                ForEach(agents) { agent in
                    Button {
                        stagingAgentId = agent.id
                        isStaging = true
                        onSelect(agent)
                    } label: {
                        HStack {
                            Text(agent.name)
                                .font(.headline)
                            Spacer()
                            if isStaging && stagingAgentId == agent.id {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.primary)
                    .disabled(isStaging)
                }
            } header: {
                Text("Send to Agent")
            }
        }
    }
}
