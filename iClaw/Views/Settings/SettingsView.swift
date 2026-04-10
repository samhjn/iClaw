import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SettingsViewModel?
    @State private var showAddProvider = false
    @State private var showDeleteConfirmation = false
    @AppStorage(BackgroundKeepAliveManager.enabledKey) private var keepAliveEnabled = false

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    settingsList(vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(L10n.Settings.title)
            .sheet(isPresented: $showAddProvider) {
                if let vm = viewModel {
                    LLMProviderEditView(viewModel: vm)
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = SettingsViewModel(modelContext: modelContext)
            } else {
                viewModel?.fetchProviders()
            }
        }
    }

    private func settingsList(_ vm: SettingsViewModel) -> some View {
        List {
            Section(L10n.Settings.llmProviders) {
                ForEach(vm.providers, id: \.id) { provider in
                    NavigationLink {
                        LLMProviderEditView(viewModel: vm, existingProvider: provider)
                    } label: {
                        let row = vm.providerRowCache[provider.id]
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row?.name ?? "")
                                    .font(.headline)
                                HStack(spacing: 4) {
                                    Text(row?.modelName ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let extra = row?.extraModelCount, extra > 0 {
                                        Text("+\(extra)")
                                            .font(.caption2)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(.blue.opacity(0.7)))
                                    }
                                }
                                Text(row?.endpoint ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if vm.defaultProviderId == provider.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            vm.confirmDeleteProvider(provider)
                            showDeleteConfirmation = true
                        } label: {
                            Label(L10n.Common.delete, systemImage: "trash")
                        }
                        if vm.defaultProviderId != provider.id {
                            Button {
                                vm.setDefault(provider)
                            } label: {
                                Label(L10n.Common.defaultLabel, systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                    }
                    .contextMenu {
                        if vm.defaultProviderId != provider.id {
                            Button {
                                vm.setDefault(provider)
                            } label: {
                                Label(L10n.Common.defaultLabel, systemImage: "checkmark.circle")
                            }
                        }
                        Button(role: .destructive) {
                            vm.confirmDeleteProvider(provider)
                            showDeleteConfirmation = true
                        } label: {
                            Label(L10n.Common.delete, systemImage: "trash")
                        }
                    }
                }

                Button {
                    showAddProvider = true
                } label: {
                    Label(L10n.Settings.addProvider, systemImage: "plus")
                }
            }

            Section {
                Toggle(L10n.Settings.backgroundKeepAlive, isOn: $keepAliveEnabled)
            } header: {
                Text(L10n.Settings.backgroundExecution)
            } footer: {
                Text(L10n.Settings.backgroundKeepAliveFooter)
            }

            Section(L10n.Settings.about) {
                NavigationLink {
                    AboutView()
                } label: {
                    HStack {
                        Text(L10n.Settings.about)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        // Use a plain @State bool — NOT a custom Binding derived from
        // @Observable state. Custom bindings trigger dispatchImmediately
        // during alert dismissal, re-entering the render cycle and
        // crashing the UICollectionView batch update.
        .alert(L10n.Settings.deleteProviderTitle, isPresented: $showDeleteConfirmation) {
            Button(L10n.Common.delete, role: .destructive) {
                if let provider = vm.providerToDelete {
                    vm.deleteProvider(provider)
                }
                vm.providerToDelete = nil
                vm.affectedAgentNames = []
            }
            Button(L10n.Common.cancel, role: .cancel) {
                vm.providerToDelete = nil
                vm.affectedAgentNames = []
            }
        } message: {
            if vm.affectedAgentNames.isEmpty {
                Text(L10n.Settings.deleteProviderMessage)
            } else {
                Text(L10n.Settings.deleteProviderAffectedMessage(
                    vm.affectedAgentNames.joined(separator: ", ")
                ))
            }
        }
    }
}
