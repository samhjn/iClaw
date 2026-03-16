import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    let session: Session
    @State private var viewModel: ChatViewModel?
    @State private var showTitleEditor = false
    @State private var editingTitle = ""

    var body: some View {
        Group {
            if let vm = viewModel {
                ChatContentView(vm: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        editingTitle = session.title
                        showTitleEditor = true
                    } label: {
                        Label(L10n.Chat.rename, systemImage: "pencil")
                    }

                    if let vm = viewModel {
                        let stats = vm.compressionStats

                        Section {
                            Button {
                                vm.manualCompress()
                            } label: {
                                Label(L10n.Chat.compressContext, systemImage: "arrow.down.right.and.arrow.up.left")
                            }
                            .disabled(vm.isCompressing || vm.isLoading)
                        }

                        Section {
                            Label {
                                Text(L10n.Chat.tokenUsage(active: stats.activeFormatted, threshold: stats.thresholdFormatted))
                            } icon: {
                                Image(systemName: "gauge.medium")
                            }
                            Label {
                                Text(L10n.Chat.messageStats(total: stats.totalMessages, compressed: stats.compressedCount))
                            } icon: {
                                Image(systemName: "doc.text")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                }
            }
        }
        .alert(L10n.Chat.renameSession, isPresented: $showTitleEditor) {
            TextField(L10n.Chat.title, text: $editingTitle)
            Button(L10n.Common.save) {
                let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    viewModel?.setCustomTitle(trimmed)
                }
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        }
        .onAppear {
            if viewModel == nil {
                viewModel = ChatViewModel(session: session, modelContext: modelContext)
            } else {
                viewModel?.onViewAppear()
            }
        }
        .onDisappear {
            viewModel?.onViewDisappear()
        }
    }
}

private struct ChatContentView: View {
    @Bindable var vm: ChatViewModel
    @State private var scrollPosition: UUID?
    @State private var hasRestoredScroll = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.messages, id: \.id) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }

                        if vm.isLoading && !vm.streamingContent.isEmpty {
                            MessageBubbleView(
                                streamingContent: vm.streamingContent
                            )
                            .id("streaming")
                        }

                        if vm.isLoading && vm.streamingContent.isEmpty && !vm.isCompressing {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 4)
                                if vm.isCancelling {
                                    Text(L10n.Chat.cancelling)
                                        .font(.subheadline)
                                        .foregroundStyle(.orange)
                                } else {
                                    Text(L10n.Chat.thinking)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .id("loading")
                        }

                        if vm.isCompressing {
                            CompressionPanel(stats: vm.compressionStats, isCancelling: vm.isCancellingCompression) {
                                vm.cancelCompression()
                            }
                            .id("compressing")
                        }
                    }
                    .padding()
                }
                .scrollPosition(id: $scrollPosition, anchor: .top)
                .onAppear {
                    if !hasRestoredScroll {
                        hasRestoredScroll = true
                        if let target = vm.initialScrollTarget {
                            DispatchQueue.main.async {
                                proxy.scrollTo(target, anchor: .top)
                            }
                        } else if let lastId = vm.messages.last?.id {
                            DispatchQueue.main.async {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: vm.messages.count) {
                    withAnimation {
                        proxy.scrollTo(vm.messages.last?.id, anchor: .bottom)
                    }
                }
                .onChange(of: vm.streamingContent) {
                    withAnimation {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
                .onDisappear {
                    if let visibleId = scrollPosition {
                        vm.saveScrollPosition(visibleId)
                    } else if let lastId = vm.messages.last?.id {
                        vm.saveScrollPosition(lastId)
                    }
                }
            }

            if let error = vm.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.Common.dismiss) {
                        vm.errorMessage = nil
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }

            if let reason = vm.sendBlockedReason {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        vm.checkActiveSessionLock()
                    } label: {
                        Text(L10n.Common.refresh)
                            .font(.caption)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
            }

            if let modelName = vm.activeModelName {
                Text(modelName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 2)
            }

            InputBarView(
                text: $vm.inputText,
                isLoading: vm.isLoading,
                isCompressing: vm.isCompressing && !vm.isLoading,
                isBlocked: !vm.canSend,
                isCancelling: vm.isCancelling,
                cancelFailureReason: vm.cancelFailureReason,
                onSend: { vm.sendMessage() },
                onStop: { vm.cancelGeneration() },
                onStopCompression: { vm.cancelCompression() },
                onDismissKeyboard: {}
            )
        }
    }
}

// MARK: - Compression Panel

private struct CompressionPanel: View {
    let stats: CompressionStats
    let isCancelling: Bool
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)

                Text(L10n.Chat.compressingContext)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .disabled(isCancelling)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))

                    Capsule()
                        .fill(tokenColor(for: stats.tokenRatio))
                        .frame(width: geo.size.width * min(CGFloat(stats.tokenRatio), 1.0))
                }
            }
            .frame(height: 6)

            HStack {
                Text(L10n.Chat.tokenUsage(active: stats.activeFormatted, threshold: stats.thresholdFormatted))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if stats.pendingCount > 0 {
                    Text(L10n.Chat.pendingCompression(stats.pendingCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 4)
    }
}

private func tokenColor(for ratio: Double) -> Color {
    switch ratio {
    case ..<0.6: return .green
    case ..<0.85: return .yellow
    case ..<1.0: return .orange
    default: return .red
    }
}
