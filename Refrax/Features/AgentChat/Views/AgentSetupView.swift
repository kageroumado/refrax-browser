import SwiftUI

/// Inline onboarding view shown when no agent credentials are configured.
///
/// Presents a compact API key entry for the currently selected provider,
/// plus a link to open the full configuration sheet for switching
/// providers or adjusting advanced options.
struct AgentSetupView: View {
    let onCredentialConfigured: () -> Void

    @Environment(BrowserSettings.self) private var settings

    @State private var apiKeyInput = ""
    @State private var baseURLInput = ""
    @State private var showConfigSheet = false

    private var activeProvider: AgentProviderKind {
        settings.agentProviderKind
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.purple.opacity(0.6))

            Text("Agent Chat")
                .font(.title2)
                .foregroundStyle(.primary)

            Text("Chat with your AI about this page,\nresearch topics, or get help.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            @Bindable var s = settings

            VStack(alignment: .leading, spacing: 8) {
                Text("Provider")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)

                Picker("Provider", selection: $s.agentProviderKind) {
                    ForEach(AgentProviderKind.allCases, id: \.self) { kind in
                        Text(kind.shortLabel).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .onChange(of: settings.agentProviderKind) {
                    syncInputsFromProvider()
                }

                credentialFields

                Button {
                    commit()
                    onCredentialConfigured()
                } label: {
                    Label("Connect", systemImage: "bolt.horizontal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canConnect)
                .accessibilityIdentifier("agent-setup-connect")

                Text("API keys are stored in your macOS Keychain.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)

            Button("More options…") {
                showConfigSheet = true
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .buttonStyle(.plain)

            Text("Tip: ⌘⌃S to toggle chat")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showConfigSheet) {
            AgentConfigSheet()
                .environment(settings)
        }
        .onAppear(perform: syncInputsFromProvider)
    }

    // MARK: - Credential Fields

    @ViewBuilder
    private var credentialFields: some View {
        switch activeProvider {
        case .claudeAPI:
            labeledField(
                title: "Anthropic API Key",
                placeholder: "sk-ant-...",
            )
        case .openAI:
            labeledField(
                title: "OpenAI API Key",
                placeholder: "sk-...",
            )
        case .openRouter:
            labeledField(
                title: "OpenRouter API Key",
                placeholder: "sk-or-...",
            )
        case .custom:
            VStack(alignment: .leading, spacing: 6) {
                Text("Base URL")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                TextField("http://localhost:11434/v1", text: $baseURLInput)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("agent-setup-base-url")
                Text("Optional API key")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.top, 4)
                SecureField("Leave blank for unauthenticated local servers", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("agent-setup-api-key-field")
            }
        }
    }

    private func labeledField(title: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
            SecureField(placeholder, text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("agent-setup-api-key-field")
        }
    }

    // MARK: - State sync

    private var canConnect: Bool {
        switch activeProvider {
        case .claudeAPI, .openAI, .openRouter:
            !apiKeyInput.isEmpty
        case .custom:
            !baseURLInput.isEmpty
                && URL(string: baseURLInput) != nil
        }
    }

    private func syncInputsFromProvider() {
        apiKeyInput = AgentCredentialStore.loadAPIKey(for: activeProvider) ?? ""
        if activeProvider == .custom {
            baseURLInput = settings.agentCustomBaseURL
        }
    }

    private func commit() {
        if !apiKeyInput.isEmpty {
            AgentCredentialStore.storeAPIKey(apiKeyInput, for: activeProvider)
        }
        if activeProvider == .custom {
            settings.agentCustomBaseURL = baseURLInput
            settings.agentCustomRequiresAuth = !apiKeyInput.isEmpty
        }
    }
}
