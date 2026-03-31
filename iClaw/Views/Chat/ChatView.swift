import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    let session: Session
    @State private var viewModel: ChatViewModel?
    @State private var showTitleEditor = false
    @State private var editingTitle = ""

    private func ensureViewModel() -> ChatViewModel {
        if let vm = viewModel { return vm }
        let vm = ChatViewModel(session: session, modelContext: modelContext)
        viewModel = vm
        return vm
    }

    var body: some View {
        let vm = ensureViewModel()
        ChatContentView(vm: vm)
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
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vm.isVerbose = true
                            }
                        } label: {
                            Label {
                                Text(L10n.Chat.verbose)
                            } icon: {
                                if vm.isVerbose {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vm.isVerbose = false
                            }
                        } label: {
                            Label {
                                Text(L10n.Chat.silent)
                            } icon: {
                                if !vm.isVerbose {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } header: {
                        if let agentName = session.agent?.name {
                            Text(L10n.Chat.displayModeScope(agentName))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: vm.isVerbose ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.caption2)
                        Text(vm.isVerbose ? L10n.Chat.verbose : L10n.Chat.silent)
                            .font(.caption2.weight(.medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(vm.isVerbose ? Color.accentColor.opacity(0.12) : Color(.systemGray5))
                    )
                    .foregroundStyle(vm.isVerbose ? Color.accentColor : .secondary)
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
            viewModel?.onViewAppear()
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
                            MessageBubbleView(message: message, isVerbose: vm.isVerbose)
                                .id(message.id)
                        }

                        if vm.isLoading && (!vm.streamingContent.isEmpty || (vm.isVerbose && !vm.streamingThinking.isEmpty)) {
                            MessageBubbleView(
                                streamingContent: vm.streamingContent,
                                streamingThinking: vm.isVerbose ? vm.streamingThinking : nil,
                                isVerbose: vm.isVerbose
                            )
                            .id("streaming")
                        }

                        if vm.isLoading && vm.streamingContent.isEmpty && (vm.isVerbose ? vm.streamingThinking.isEmpty : true) && !vm.isCompressing {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 4)
                                if vm.isCancelling {
                                    Text(L10n.Chat.cancelling)
                                        .font(.subheadline)
                                        .foregroundStyle(.orange)
                                } else if !vm.isVerbose {
                                    TimelineView(.periodic(from: .now, by: 0.3)) { _ in
                                        silentLabel(for: vm.silentStatus)
                                    }
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
                        .lineLimit(3)
                    Spacer()
                    Button {
                        vm.retryGeneration()
                    } label: {
                        Label(L10n.Chat.retry, systemImage: "arrow.clockwise")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .tint(.accentColor)
                    Button {
                        UIPasteboard.general.string = error
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    Button {
                        vm.dismissRetry()
                    } label: {
                        Text(L10n.Common.dismiss)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if vm.canRetry && !vm.isLoading {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text(L10n.Chat.retryHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        vm.retryGeneration()
                    } label: {
                        Text(L10n.Chat.retry)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .tint(.accentColor)
                    Button {
                        vm.dismissRetry()
                    } label: {
                        Text(L10n.Common.dismiss)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.06))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let warning = vm.modalityWarning {
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.Common.dismiss) {
                        vm.modalityWarning = nil
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.yellow.opacity(0.08))
            }

            if let warning = vm.toolUseWarning {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.trianglebadge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.Common.dismiss) {
                        vm.toolUseWarning = nil
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
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
                canRetry: vm.canRetry,
                cancelFailureReason: vm.cancelFailureReason,
                pendingImages: vm.pendingImages,
                isImageDisabled: vm.session.agent.map { $0.permissionLevel(for: .files) == .disabled } ?? false,
                onSend: { vm.sendMessage() },
                onStop: { vm.cancelGeneration() },
                onStopCompression: { vm.cancelCompression() },
                onRetry: { vm.retryGeneration() },
                onDismissKeyboard: {},
                onAddImage: { vm.addImage($0) },
                onRemoveImage: { vm.removeImage(id: $0) }
            )
        }
        .animation(.easeInOut(duration: 0.25), value: vm.canRetry)
        .animation(.easeInOut(duration: 0.25), value: vm.isLoading)
        .animation(.easeInOut(duration: 0.25), value: vm.errorMessage)
        .animation(.easeInOut(duration: 0.2), value: vm.silentStatus)
    }

    @ViewBuilder
    private func silentLabel(for status: String) -> some View {
        if status.hasPrefix("tool:") {
            let name = String(status.dropFirst(5))
            let meta = ToolMeta.resolve(name)
            HStack(spacing: 6) {
                Image(systemName: meta.icon)
                    .font(.caption)
                    .foregroundStyle(meta.color)
                Text(meta.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if status.hasPrefix("think:"), let n = Int(status.dropFirst(6)), n > 1 {
            HStack(spacing: 6) {
                Text(L10n.Chat.silentThinking(n))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let lastTool = vm.silentLastTool {
                    let meta = ToolMeta.resolve(lastTool)
                    Image(systemName: meta.icon)
                        .font(.caption2)
                        .foregroundStyle(meta.color.opacity(0.6))
                }
            }
        } else {
            Text(L10n.Chat.thinking)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
