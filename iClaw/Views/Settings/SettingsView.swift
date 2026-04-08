import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SettingsViewModel?
    @State private var showAddProvider = false

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
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .font(.headline)
                                HStack(spacing: 4) {
                                    Text(provider.modelName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    let extraCount = provider.enabledModels.count - 1
                                    if extraCount > 0 {
                                        Text("+\(extraCount)")
                                            .font(.caption2)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(.blue.opacity(0.7)))
                                    }
                                }
                                Text(provider.endpoint)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if provider.isDefault {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            vm.confirmDeleteProvider(provider)
                        } label: {
                            Label(L10n.Common.delete, systemImage: "trash")
                        }
                        if !provider.isDefault {
                            Button {
                                vm.setDefault(provider)
                            } label: {
                                Label(L10n.Common.defaultLabel, systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                    }
                    .contextMenu {
                        if !provider.isDefault {
                            Button {
                                vm.setDefault(provider)
                            } label: {
                                Label(L10n.Common.defaultLabel, systemImage: "checkmark.circle")
                            }
                        }
                        Button(role: .destructive) {
                            vm.confirmDeleteProvider(provider)
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
        .alert(L10n.Settings.deleteProviderTitle, isPresented: Binding(
            get: { vm.providerToDelete != nil },
            set: { if !$0 { vm.providerToDelete = nil; vm.affectedAgentNames = [] } }
        )) {
            Button(L10n.Common.delete, role: .destructive) {
                if let provider = vm.providerToDelete {
                    vm.deleteProvider(provider)
                }
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
