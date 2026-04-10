import SwiftUI

struct MessageBubbleView: View {
    var message: Message?
    var streamingContent: String?
    var streamingThinking: String?
    var isVerbose: Bool = true

    @State private var cache = DecodedCache()

    private final class DecodedCache {
        var toolCalls: [LLMToolCall]??
        var imageAttachments: [ImageAttachment]?
    }

    private var role: MessageRole {
        message?.role ?? .assistant
    }

    private var content: String {
        streamingContent ?? message?.content ?? ""
    }

    private var isUser: Bool {
        role == .user
    }

    private var isTool: Bool {
        role == .tool
    }

    private var isAssistant: Bool {
        role == .assistant
    }

    private var isStreaming: Bool {
        streamingContent != nil
    }

    private var toolCalls: [LLMToolCall]? {
        if let cached = cache.toolCalls { return cached }
        let result: [LLMToolCall]? = {
            guard let data = message?.toolCallsData else { return nil }
            return try? JSONDecoder().decode([LLMToolCall].self, from: data)
        }()
        cache.toolCalls = .some(result)
        return result
    }

    private var imageAttachments: [ImageAttachment] {
        if let cached = cache.imageAttachments { return cached }
        let result: [ImageAttachment] = {
            guard let data = message?.imageAttachmentsData else { return [] }
            return (try? JSONDecoder().decode([ImageAttachment].self, from: data)) ?? []
        }()
        cache.imageAttachments = result
        return result
    }

    /// True when the rendered content already references images inline via `attachment:N` or `agentfile://`.
    private var contentHasInlineImageRefs: Bool {
        content.contains("attachment:") || content.contains("agentfile://")
    }

    /// User message display content with `agentfile://` image refs stripped
    /// (images are already shown in the grid via imageAttachmentsData).
    private var userDisplayContent: String {
        guard content.contains("agentfile://") else { return content }
        let pattern = "\\n?!\\[[^\\]]*\\]\\(agentfile://[^)]+\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return content }
        let range = NSRange(content.startIndex..., in: content)
        return regex.stringByReplacingMatches(in: content, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let imageMarkdownPattern = try! NSRegularExpression(
        pattern: "!\\[[^\\]]*\\]\\([^)]+\\)",
        options: []
    )

    private static func sanitizeForCopy(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return imageMarkdownPattern.stringByReplacingMatches(
            in: text, options: [], range: range, withTemplate: L10n.Chat.imagePlaceholder
        )
    }

    /// The best copyable text for this message.
    private var copyableText: String {
        if let msg = message {
            if msg.role == .tool {
                return "[\(msg.name ?? "tool")] \(msg.content ?? "")"
            }
            if let calls = toolCalls, !calls.isEmpty {
                var parts: [String] = []
                if let c = msg.content, !c.isEmpty { parts.append(Self.sanitizeForCopy(c)) }
                for call in calls {
                    parts.append("[\(call.function.name)] \(call.function.arguments)")
                }
                return parts.joined(separator: "\n\n")
            }
            return Self.sanitizeForCopy(msg.content ?? "")
        }
        return Self.sanitizeForCopy(streamingContent ?? "")
    }

    /// In silent mode, hide tool results and content-less assistant messages with tool calls.
    private var shouldHideInSilentMode: Bool {
        guard !isVerbose else { return false }
        if isTool { return true }
        if isAssistant, let calls = toolCalls, !calls.isEmpty, content.isEmpty { return true }
        return false
    }

    var body: some View {
        if shouldHideInSilentMode {
            EmptyView()
        } else {
            messageBody
        }
    }

    @ViewBuilder
    private var messageBody: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if isTool {
                    ToolResultCardView(message: message!)
                        .messageContextMenu(text: copyableText)
                } else if let calls = toolCalls, !calls.isEmpty {
                    assistantWithToolCalls(calls)
                        .messageContextMenu(text: copyableText)
                } else {
                    bubbleView
                        .messageContextMenu(text: copyableText)
                }

                if let msg = message {
                    Text(msg.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !isUser { Spacer(minLength: 48) }
        }
    }

    private var thinkingText: String? {
        if let streaming = streamingThinking, !streaming.isEmpty { return streaming }
        return message?.thinkingContent
    }

    private var isStreamingThinking: Bool {
        streamingThinking != nil && !(streamingThinking?.isEmpty ?? true)
    }

    @ViewBuilder
    private var bubbleView: some View {
        if isUser {
            VStack(alignment: .trailing, spacing: 6) {
                if !imageAttachments.isEmpty {
                    MessageImageGrid(images: imageAttachments)
                }
                if !userDisplayContent.isEmpty {
                    Text(userDisplayContent)
                        .font(.body)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.accentColor)
                        )
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if isVerbose, let thinking = thinkingText, !thinking.isEmpty {
                    ThinkingBubbleView(content: thinking, isStreaming: isStreamingThinking)
                }

                if !content.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        MarkdownContentView(content, isUser: false, imageAttachments: imageAttachments)
                        if isStreaming {
                            StreamingDotsView()
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                    )
                    .foregroundStyle(.primary)
                }

                if !imageAttachments.isEmpty && !contentHasInlineImageRefs {
                    MessageImageGrid(images: imageAttachments)
                }
            }
        }
    }

    @ViewBuilder
    private func assistantWithToolCalls(_ calls: [LLMToolCall]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isVerbose, let thinking = thinkingText, !thinking.isEmpty {
                ThinkingBubbleView(content: thinking, isStreaming: false)
            }

            if !content.isEmpty {
                MarkdownContentView(content, isUser: false, imageAttachments: imageAttachments)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                    )
                    .foregroundStyle(.primary)
            }

            if !imageAttachments.isEmpty && !contentHasInlineImageRefs {
                MessageImageGrid(images: imageAttachments)
            }

            if isVerbose {
                ToolCallCardView(toolCalls: calls)
            }
        }
    }
}

// MARK: - Image Grid for User Messages

private struct MessageImageGrid: View {
    let images: [ImageAttachment]

    var body: some View {
        let columns = images.count == 1
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]

        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(images) { attachment in
                CachedImageCell(attachment: attachment, isSingle: images.count == 1)
            }
        }
    }
}

private struct CachedImageCell: View {
    let attachment: ImageAttachment
    let isSingle: Bool

    @State private var resolved: UIImage?
    @State private var deleted = false
    @State private var hasResolved = false

    private var maxW: CGFloat { isSingle ? 240 : 140 }
    private var maxH: CGFloat { isSingle ? 240 : 140 }

    var body: some View {
        Group {
            if deleted {
                ZStack {
                    if let thumb = attachment.thumbnailImage {
                        Image(uiImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 3)
                    } else {
                        Color(.systemGray5)
                    }
                    Color.black.opacity(0.5)
                    VStack(spacing: 4) {
                        Image(systemName: "trash.slash")
                            .font(.title3)
                        Text(L10n.Chat.imageDeleted)
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)
                }
                .frame(maxWidth: maxW, maxHeight: maxH)
                .frame(minHeight: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let uiImage = resolved {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: maxW, maxHeight: maxH)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        ImagePreviewCoordinator.shared.show(uiImage)
                    }
            }
        }
        .onAppear {
            guard !hasResolved else { return }
            hasResolved = true
            deleted = attachment.isFileDeleted
            if !deleted {
                resolved = attachment.uiImage
            }
        }
    }
}

// MARK: - Context Menu Modifier

private struct MessageContextMenuModifier: ViewModifier {
    let textProvider: () -> String
    @State private var showCopied = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                let text = textProvider()

                Button {
                    UIPasteboard.general.string = text
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopied = false
                    }
                } label: {
                    Label(L10n.Common.copy, systemImage: "doc.on.doc")
                }

                if let url = URL(string: text), UIApplication.shared.canOpenURL(url) {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Label(L10n.Chat.openLink, systemImage: "safari")
                    }
                }

                Button {
                    let activityVC = UIActivityViewController(
                        activityItems: [text],
                        applicationActivities: nil
                    )
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController {
                        var topVC = rootVC
                        while let presented = topVC.presentedViewController {
                            topVC = presented
                        }
                        if let popover = activityVC.popoverPresentationController {
                            popover.sourceView = topVC.view
                            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                            popover.permittedArrowDirections = []
                        }
                        topVC.present(activityVC, animated: true)
                    }
                } label: {
                    Label(L10n.Chat.share, systemImage: "square.and.arrow.up")
                }
            }
            .overlay(alignment: .top) {
                if showCopied {
                    Text(L10n.Common.copied)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.7)))
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeOut(duration: 0.2), value: showCopied)
                }
            }
    }
}

extension View {
    func messageContextMenu(text: @escaping @autoclosure () -> String) -> some View {
        modifier(MessageContextMenuModifier(textProvider: text))
    }
}

// MARK: - Streaming Dots

private struct StreamingDotsView: View {
    @State private var phase = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 5, height: 5)
                    .scaleEffect(phase == index ? 1.3 : 0.7)
                    .opacity(phase == index ? 1.0 : 0.5)
                    .animation(.easeInOut(duration: 0.4), value: phase)
            }
        }
        .padding(.top, 2)
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}
