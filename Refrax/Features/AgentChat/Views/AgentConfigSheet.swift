import SwiftUI
import UniformTypeIdentifiers

/// Sheet for configuring agent provider, credentials, and display settings.
struct AgentConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BrowserSettings.self) private var settings

    @State private var displayName: String = ""
    @State private var avatarImage: NSImage?
    @State private var showImagePicker = false

    /// Credential buffers keyed by provider. Loaded on appear; written to
    /// the Keychain whenever the active provider's key changes.
    @State private var apiKeyInputs: [AgentProviderKind: String] = [:]

    var body: some View {
        VStack(spacing: 20) {
            header
            Divider()
            providerSection
            Divider()
            generalSection
            Spacer()
            footer
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 560)
        .onAppear(perform: loadInitialState)
        .fileImporter(
            isPresented: $showImagePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false,
        ) { result in
            handleImageSelection(result)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            Button {
                showImagePicker = true
            } label: {
                avatarPreview
                    .frame(width: 60, height: 60)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white, Color.appAccentColor)
                            .offset(x: 3, y: 3)
                    }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text("Display Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Agent", text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Provider Section

    @ViewBuilder
    private var providerSection: some View {
        @Bindable var s = settings
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Provider")
                    .font(.callout.weight(.medium))
                Picker("Provider", selection: $s.agentProviderKind) {
                    ForEach(AgentProviderKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            switch settings.agentProviderKind {
            case .claudeAPI: claudeSettings
            case .openAI: openAISettings
            case .openRouter: openRouterSettings
            case .custom: customSettings
            }
        }
    }

    // MARK: - Claude

    private var claudeSettings: some View {
        @Bindable var s = settings
        return VStack(alignment: .leading, spacing: 12) {
            apiKeyField(
                provider: .claudeAPI,
                label: "Anthropic API Key",
                placeholder: "sk-ant-...",
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Model")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AgentModelPicker(
                    provider: .claudeAPI,
                    selection: $s.agentClaudeModel,
                    baseURL: nil,
                    apiKey: nil,
                    extraHeaders: [:],
                )
            }

            HStack {
                Text("Max Tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper(
                    "\(settings.agentClaudeMaxTokens)",
                    value: $s.agentClaudeMaxTokens,
                    in: 1_024 ... 32_768,
                    step: 1_024,
                )
                .font(.callout)
            }
        }
    }

    // MARK: - OpenAI

    private var openAISettings: some View {
        @Bindable var s = settings
        return VStack(alignment: .leading, spacing: 12) {
            apiKeyField(
                provider: .openAI,
                label: "OpenAI API Key",
                placeholder: "sk-...",
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Model")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AgentModelPicker(
                    provider: .openAI,
                    selection: $s.agentOpenAIModel,
                    baseURL: URL(string: "https://api.openai.com/v1"),
                    apiKey: apiKeyInputs[.openAI],
                    extraHeaders: [:],
                )
            }

            maxCompletionTokensField
        }
    }

    // MARK: - OpenRouter

    private var openRouterSettings: some View {
        @Bindable var s = settings
        return VStack(alignment: .leading, spacing: 12) {
            apiKeyField(
                provider: .openRouter,
                label: "OpenRouter API Key",
                placeholder: "sk-or-...",
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Model")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AgentModelPicker(
                    provider: .openRouter,
                    selection: $s.agentOpenRouterModel,
                    baseURL: URL(string: "https://openrouter.ai/api/v1"),
                    apiKey: apiKeyInputs[.openRouter],
                    extraHeaders: [
                        "HTTP-Referer": "https://refrax.website",
                        "X-Title": "Refrax",
                    ],
                )
            }

            Text("Refrax identifies itself to OpenRouter with `HTTP-Referer` and `X-Title` so the model lands on Refrax's app usage.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            maxCompletionTokensField
        }
    }

    // MARK: - Custom

    private var customSettings: some View {
        @Bindable var s = settings
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Base URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("http://localhost:11434/v1", text: $s.agentCustomBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .textContentType(.URL)
                    .autocorrectionDisabled(true)
                Text("Point at any OpenAI-compatible endpoint — Ollama, LM Studio, llama.cpp, vLLM, or a self-hosted proxy. Include the `/v1` suffix.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Toggle("Endpoint requires an API key", isOn: $s.agentCustomRequiresAuth)
                .font(.callout)

            if settings.agentCustomRequiresAuth {
                apiKeyField(
                    provider: .custom,
                    label: "API Key",
                    placeholder: "Bearer token",
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Model")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AgentModelPicker(
                    provider: .custom,
                    selection: $s.agentCustomModel,
                    baseURL: URL(string: settings.agentCustomBaseURL),
                    apiKey: settings.agentCustomRequiresAuth ? apiKeyInputs[.custom] : nil,
                    extraHeaders: [:],
                )
            }

            maxCompletionTokensField
        }
    }

    private var maxCompletionTokensField: some View {
        @Bindable var s = settings
        return HStack {
            Text("Max Completion Tokens")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Stepper(
                "\(settings.agentOpenAIMaxTokens)",
                value: $s.agentOpenAIMaxTokens,
                in: 512 ... 16_384,
                step: 512,
            )
            .font(.callout)
        }
    }

    // MARK: - API Key Field

    private func apiKeyField(
        provider: AgentProviderKind,
        label: String,
        placeholder: String,
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if AgentCredentialStore.hasAPIKey(for: provider) {
                    Button("Clear", role: .destructive) {
                        apiKeyInputs[provider] = ""
                        AgentCredentialStore.deleteAPIKey(for: provider)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }

            SecureField(placeholder, text: Binding(
                get: { apiKeyInputs[provider] ?? "" },
                set: { newValue in
                    apiKeyInputs[provider] = newValue
                    AgentCredentialStore.storeAPIKey(newValue, for: provider)
                },
            ))
            .textFieldStyle(.roundedBorder)
            .font(.callout)

            Text("Stored in your macOS Keychain")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - General

    private var generalSection: some View {
        @Bindable var s = settings
        return VStack(alignment: .leading, spacing: 12) {
            Toggle("Auto-include browser context", isOn: $s.agentAutoIncludeContext)
                .font(.callout)

            VStack(alignment: .leading, spacing: 6) {
                Text("Custom Instructions")
                    .font(.callout.weight(.medium))
                Text("Add custom instructions to the agent's system prompt via an AGENTS.md file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Edit AGENTS.md") {
                    openAgentsMD()
                }
                .font(.callout)
                Text(Directories.appStorage.appending(path: "AGENTS.md").path(percentEncoded: false))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if settings.agentAvatarData != nil {
                Button("Remove Avatar", role: .destructive) {
                    settings.agentAvatarData = nil
                    avatarImage = nil
                }
            }

            Spacer()

            Button("Cancel", role: .cancel) {
                dismiss()
            }

            Button("Save") {
                save()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatarPreview: some View {
        if let image = avatarImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
        }
    }

    // MARK: - Handlers

    private func loadInitialState() {
        displayName = settings.agentDisplayName
        if let data = settings.agentAvatarData {
            avatarImage = NSImage(data: data)
        }
        for provider in AgentProviderKind.allCases {
            apiKeyInputs[provider] = AgentCredentialStore.loadAPIKey(for: provider) ?? ""
        }
    }

    private func handleImageSelection(_ result: Result<[URL], any Error>) {
        guard case let .success(urls) = result,
              let url = urls.first,
              url.startAccessingSecurityScopedResource() else {
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        if let image = NSImage(contentsOf: url) {
            avatarImage = image
        }
    }

    private func openAgentsMD() {
        let url = Directories.appStorage.appending(path: "AGENTS.md")
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            let template = """
            # Agent Custom Instructions

            Add instructions here to customize the agent's behavior.
            These are appended to the system prompt for every conversation.

            Examples:
            - Preferred language or tone
            - Domain-specific knowledge or terminology
            - Default workflows or automation preferences
            """
            try? template.data(using: .utf8)?.write(to: url)
        }
        NSWorkspace.shared.open(url)
    }

    private func save() {
        settings.agentDisplayName = displayName.isEmpty ? "Agent" : displayName

        if let image = avatarImage,
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            settings.agentAvatarData = pngData
        }
    }
}

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    AgentConfigSheet()
}
