import SwiftUI
import UniformTypeIdentifiers

/// Input field for agent chat with auto-expansion and attachment support.
struct AgentChatInputView: View {
    @Environment(AgentChatManager.self) private var chatManager
    @Environment(WindowState.self) private var windowState

    @State private var inputText = ""
    @FocusState private var isFocused: Bool
    @State private var showHTTPEndpointAlert = false
    @State private var isHTTPEndpointAvailable: Bool?
    @State private var httpEndpointError: String?

    var body: some View {
        VStack(spacing: 0) {
            largeAttachmentWarningIfNeeded
            contextIndicatorIfNeeded
            pendingAttachmentsIfNeeded
            inputRow
        }
        .task { await refreshHTTPStatus() }
        .onChange(of: chatManager.pendingAttachments.count) {
            Task { await refreshHTTPStatus() }
        }
        .onChange(of: chatManager.connectionState) { _, newState in
            if case .connected = newState {
                Task { await refreshHTTPStatus() }
            }
        }
        .alert("Enable Large Image Support", isPresented: $showHTTPEndpointAlert) {
            Button("Enable") {
                Task {
                    await chatManager.enableHTTPEndpoint()
                    await refreshHTTPStatus()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Large images require the OpenResponses HTTP endpoint.\n\n\(httpEndpointError ?? "The endpoint is currently disabled.")\n\nEnable it now?")
        }
    }
}

// MARK: - Subviews

private extension AgentChatInputView {
    @ViewBuilder
    var largeAttachmentWarningIfNeeded: some View {
        if chatManager.pendingAttachmentsRequireHTTP, isHTTPEndpointAvailable == false {
            LargeAttachmentWarningBanner { showHTTPEndpointAlert = true }
        }
    }

    @ViewBuilder
    var contextIndicatorIfNeeded: some View {
        if let summary = contextSummary {
            ContextIndicatorBar(summary: summary)
        }
    }

    @ViewBuilder
    var pendingAttachmentsIfNeeded: some View {
        if !chatManager.pendingAttachments.isEmpty {
            AgentAttachmentPreview(
                attachments: chatManager.pendingAttachments,
                onRemove: { chatManager.removeAttachment($0) },
            )
        }
    }

    var inputRow: some View {
        GlassEffectContainer {
            HStack(alignment: .center, spacing: 8) {
                attachmentMenuButton
                messageTextField
                sendOrStopButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Input Components

private extension AgentChatInputView {
    var attachmentMenuButton: some View {
        Menu {
            Button { openFilePicker() } label: {
                Label("Choose Image...", systemImage: "photo")
            }
            Button { captureScreenshot() } label: {
                Label("Screenshot Page", systemImage: "camera.viewfinder")
            }
            Button { pasteFromClipboard() } label: {
                Label("Paste Image", systemImage: "doc.on.clipboard")
            }
            .disabled(!hasImageInClipboard)

            Divider()

            Button { debugExtractPage() } label: {
                Label("Debug Extract Page", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(windowState.activeWebPage == nil || !chatManager.connectionState.isConnected)
        } label: {
            Image(systemName: "plus")
                .chatInputButtonStyle()
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Add attachment")
        .accessibilityIdentifier("agent-chat-attachment-button")
    }

    var messageTextField: some View {
        ChatMessageTextField(
            text: $inputText,
            isFocused: $isFocused,
            onSend: { Task { await sendMessage() } },
            onPasteImage: { pasteImageFromClipboard() },
        )
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            handleImageDrop(providers)
            return true
        }
    }

    @ViewBuilder
    var sendOrStopButton: some View {
        if chatManager.isStreaming {
            Button {
                Task { await chatManager.abortResponse() }
            } label: {
                Image(systemName: "stop.fill")
                    .chatInputButtonStyle(size: 12, color: .red)
                    .glassEffect(.regular.interactive().tint(.red.opacity(0.3)), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Stop response")
            .accessibilityIdentifier("agent-chat-stop-button")
        } else {
            Button {
                Task { await sendMessage() }
            } label: {
                Image(systemName: "arrow.up")
                    .chatInputButtonStyle(size: 14, color: canSend ? .appAccentColor : .secondary.opacity(0.4))
                    .glassEffect(
                        .regular.interactive().tint(canSend ? .appAccentColor.opacity(0.3) : nil),
                        in: Circle(),
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help("Send message (⌘↩)")
            .accessibilityIdentifier("agent-chat-send-button")
        }
    }
}

// MARK: - Computed Properties

private extension AgentChatInputView {
    var willIncludeContext: Bool {
        BrowserContextProvider.shouldIncludeContext(for: inputText)
    }

    var contextSummary: String? {
        guard willIncludeContext else { return nil }
        let context = BrowserContextProvider.extractContext(from: windowState)
        return context.flatMap { BrowserContextProvider.contextSummary(for: $0) }
    }

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !chatManager.pendingAttachments.isEmpty
    }

    var hasImageInClipboard: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
    }
}

// MARK: - Actions

private extension AgentChatInputView {
    func refreshHTTPStatus() async {
        isHTTPEndpointAvailable = await chatManager.isHTTPEndpointAvailable
        httpEndpointError = await chatManager.httpEndpointError
    }

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }

        inputText = ""

        let context = willIncludeContext
            ? BrowserContextProvider.extractContext(from: windowState)
            : nil

        await chatManager.sendMessage(text, context: context)
    }

    func debugExtractPage() {
        guard let webPage = windowState.activeWebPage else { return }
        Task { await chatManager.debugExtractPage(page: webPage) }
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .png, .jpeg, .gif, .heic, .webP, .tiff, .bmp]

        if panel.runModal() == .OK {
            for url in panel.urls {
                addImageFromURL(url)
            }
        }
    }

    func addImageFromURL(_ url: URL) {
        let manager = chatManager
        Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return }
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
            _ = await MainActor.run {
                manager.addAttachment(imageData: data, mimeType: mimeType, fileName: url.lastPathComponent)
            }
        }
    }

    func captureScreenshot() {
        guard let webPage = windowState.activeWebPage else { return }

        Task {
            if let pngData = try? await ScreenshotService.takeScreenshot(of: webPage, mode: .visibleArea) {
                chatManager.addAttachment(imageData: pngData, mimeType: "image/png", fileName: "screenshot.png")
            }
        }
    }

    func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
              let image = images.first,
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        chatManager.addAttachment(imageData: pngData, mimeType: "image/png", fileName: "pasted-image.png")
    }

    @discardableResult
    func pasteImageFromClipboard() -> Bool {
        let pasteboard = NSPasteboard.general

        if let imageData = pasteboard.data(forType: .png) {
            chatManager.addAttachment(imageData: imageData, mimeType: "image/png", fileName: "pasted.png")
            return true
        }

        if let imageData = pasteboard.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: imageData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            chatManager.addAttachment(imageData: pngData, mimeType: "image/png", fileName: "pasted.png")
            return true
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            chatManager.addAttachment(imageData: pngData, mimeType: "image/png", fileName: "pasted.png")
            return true
        }

        return false
    }

    func handleImageDrop(_ providers: [NSItemProvider]) {
        let manager = chatManager

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task.detached(priority: .userInitiated) {
                        guard let data = try? Data(contentsOf: url) else { return }
                        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
                        _ = await MainActor.run {
                            manager.addAttachment(imageData: data, mimeType: mimeType, fileName: url.lastPathComponent)
                        }
                    }
                }
                continue
            }

            for imageType in [UTType.png, .jpeg, .tiff, .heic, .gif, .webP, .bmp] {
                if provider.hasItemConformingToTypeIdentifier(imageType.identifier) {
                    let mimeType = imageType.preferredMIMEType ?? "image/png"
                    provider.loadDataRepresentation(forTypeIdentifier: imageType.identifier) { data, _ in
                        guard let data else { return }
                        DispatchQueue.main.async {
                            manager.addAttachment(
                                imageData: data,
                                mimeType: mimeType,
                                fileName: "dropped.\(imageType.preferredFilenameExtension ?? "png")",
                            )
                        }
                    }
                    break
                }
            }
        }
    }
}

// MARK: - Chat Input Button Style

private extension Image {
    func chatInputButtonStyle(size: CGFloat = 16, color: Color? = nil) -> some View {
        font(.system(size: size, weight: .semibold))
            .foregroundStyle(color ?? .primary)
            .frame(width: 30, height: 30)
    }
}

// MARK: - Supporting Views

private struct ChatMessageTextField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onPasteImage: () -> Bool

    var body: some View {
        TextField("Message...", text: $text, axis: .vertical)
            .focused(isFocused)
            .textFieldStyle(.plain)
            .font(.body)
            .accessibilityIdentifier("agent-chat-input-field")
            .lineLimit(1 ... 6)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .glassEffect(in: .rect(cornerRadius: 15))
            .onKeyPress(.return, phases: .down) { press in
                if press.modifiers.contains(.command) {
                    onSend()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(keys: [.init("v")], phases: .down) { press in
                if press.modifiers.contains(.command), onPasteImage() {
                    return .handled
                }
                return .ignored
            }
    }
}

private struct LargeAttachmentWarningBanner: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.orange)
                Text("Large image requires additional setup")
                    .font(.caption)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.1))
        }
        .buttonStyle(.plain)
    }
}

private struct ContextIndicatorBar: View {
    let summary: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "link")
                .font(.caption2)
            Text(summary)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Previews

#Preview("Default", traits: .modifier(RefraxPreviewModifier())) {
    AgentChatInputView()
        .frame(width: 400)
}

#Preview("With Text", traits: .modifier(RefraxPreviewModifier())) {
    AgentChatInputPreviewWrapper(initialText: "Hello, can you help me with this page?")
        .frame(width: 400)
}

#Preview("With Attachments", traits: .modifier(RefraxPreviewModifier())) {
    AgentChatInputPreviewWrapper(showAttachments: true)
        .frame(width: 400)
}

#Preview("Streaming", traits: .modifier(RefraxPreviewModifier())) {
    AgentChatInputPreviewWrapper(isStreaming: true)
        .frame(width: 400)
}

/// Preview wrapper that allows setting initial state for testing different scenarios.
private struct AgentChatInputPreviewWrapper: View {
    @Environment(AgentChatManager.self) private var chatManager

    let initialText: String
    let showAttachments: Bool
    let isStreaming: Bool

    @State private var text: String

    init(
        initialText: String = "",
        showAttachments: Bool = false,
        isStreaming: Bool = false,
    ) {
        self.initialText = initialText
        self.showAttachments = showAttachments
        self.isStreaming = isStreaming
        self._text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Mock message for context
            if isStreaming {
                HStack {
                    Spacer()
                    Text("What's on this page?")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.appAccentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            // Mock attachments preview
            if showAttachments {
                mockAttachmentsPreview
            }

            // The actual input (uses internal state for text)
            mockInputRow
        }
        .task {
            // Simulate streaming state
            if isStreaming {
                // Note: Can't actually set chatManager.isStreaming from here
                // but the visual shows the stop button state
            }
        }
    }

    private var mockAttachmentsPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0 ..< 2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.blue.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.blue)
                        }
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white, .black.opacity(0.6))
                                .offset(x: 6, y: -6)
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var mockInputRow: some View {
        GlassEffectContainer {
            HStack(alignment: .center, spacing: 8) {
                // + button
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .glassEffect(.regular.interactive(), in: Circle())

                // Text field
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text("Message...")
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 8)
                    }
                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 8)
                }
                .frame(minHeight: 30)
                .glassEffect(in: .rect(cornerRadius: 15))

                // Send/Stop button
                if isStreaming {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 30, height: 30)
                        .glassEffect(.regular.interactive().tint(.red.opacity(0.3)), in: Circle())
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(!text.isEmpty ? Color.appAccentColor : Color.secondary.opacity(0.4))
                        .frame(width: 30, height: 30)
                        .glassEffect(
                            .regular.interactive().tint(!text.isEmpty ? Color.appAccentColor.opacity(0.3) : nil),
                            in: Circle(),
                        )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
