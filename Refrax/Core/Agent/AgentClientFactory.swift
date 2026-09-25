import Foundation

/// Creates the appropriate agent chat client based on user settings.
nonisolated enum AgentClientFactory {
    /// Returns a new chat client configured for the user's chosen agent provider.
    @MainActor
    static func makeClient(settings: BrowserSettings) -> any AgentChatClientProtocol {
        switch settings.agentProviderKind {
        case .claudeCode:
            LocalCLIAgentClient(runtime: .claudeCode, model: settings.agentClaudeCodeModel)

        case .codex:
            LocalCLIAgentClient(runtime: .codex, model: settings.agentCodexModel)

        case .claudeAPI:
            ClaudeDirectClient(
                model: settings.agentClaudeModel,
                maxTokens: settings.agentClaudeMaxTokens,
            )

        case .openAI:
            OpenAICompatibleClient(
                providerKind: .openAI,
                config: makeOpenAIConfig(settings: settings),
                model: settings.agentOpenAIModel,
                maxCompletionTokens: settings.agentOpenAIMaxTokens,
            )

        case .openRouter:
            OpenAICompatibleClient(
                providerKind: .openRouter,
                config: makeOpenRouterConfig(settings: settings),
                model: settings.agentOpenRouterModel,
                maxCompletionTokens: settings.agentOpenAIMaxTokens,
            )

        case .custom:
            OpenAICompatibleClient(
                providerKind: .custom,
                config: makeCustomConfig(settings: settings),
                model: settings.agentCustomModel,
                maxCompletionTokens: settings.agentOpenAIMaxTokens,
            )
        }
    }

    /// Everything that determines which client ``makeClient(settings:)`` builds.
    ///
    /// When it changes, the existing client is stale and gets rebuilt.
    @MainActor
    static func configuration(settings: BrowserSettings) -> AgentClientConfiguration {
        let provider = settings.agentProviderKind
        let model = switch provider {
        case .claudeCode: settings.agentClaudeCodeModel
        case .codex: settings.agentCodexModel
        case .claudeAPI: settings.agentClaudeModel
        case .openAI: settings.agentOpenAIModel
        case .openRouter: settings.agentOpenRouterModel
        case .custom: settings.agentCustomModel
        }
        return AgentClientConfiguration(
            provider: provider,
            model: model,
            maxTokens: provider == .claudeAPI ? settings.agentClaudeMaxTokens : settings.agentOpenAIMaxTokens,
            baseURL: provider == .custom ? settings.agentCustomBaseURL : "",
            requiresAuth: provider == .custom && settings.agentCustomRequiresAuth,
            apiKeyHash: AgentCredentialStore.loadAPIKey(for: provider)?.hashValue,
        )
    }

    /// Whether the chosen provider has what it needs to answer: an API key,
    /// a custom endpoint, or an installed CLI.
    @MainActor
    static func isProviderConfigured(settings: BrowserSettings) -> Bool {
        let provider = settings.agentProviderKind
        switch provider {
        case .claudeCode, .codex:
            return provider.cliRuntime.flatMap(CLIAgentLocator.installedURL(for:)) != nil
        case .claudeAPI, .openAI, .openRouter:
            return AgentCredentialStore.hasAPIKey(for: provider)
        case .custom:
            return !settings.agentCustomBaseURL.isEmpty && !settings.agentCustomModel.isEmpty
        }
    }

    /// Adjusts persisted agent settings once per launch: retired Claude model
    /// identifiers move to the current default, and an unusable default
    /// provider (Claude API with no key) moves to Claude Code when it is installed.
    @MainActor
    static func applyLaunchDefaults(settings: BrowserSettings) {
        let model = ClaudeModel.migrated(settings.agentClaudeModel)
        if model != settings.agentClaudeModel {
            settings.agentClaudeModel = model
        }
        if settings.agentProviderKind == .claudeAPI,
           !AgentCredentialStore.hasAPIKey(for: .claudeAPI),
           CLIAgentLocator.installedURL(for: .claudeCode) != nil {
            settings.agentProviderKind = .claudeCode
        }
    }

    // MARK: - Provider Configs

    private static func makeOpenAIConfig(settings _: BrowserSettings) -> OpenAIProviderConfig {
        OpenAIProviderConfig(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: AgentCredentialStore.loadAPIKey(for: .openAI),
            extraHeaders: [:],
            providerName: "OpenAI",
        )
    }

    private static func makeOpenRouterConfig(settings _: BrowserSettings) -> OpenAIProviderConfig {
        OpenAIProviderConfig(
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            apiKey: AgentCredentialStore.loadAPIKey(for: .openRouter),
            extraHeaders: [
                "HTTP-Referer": "https://kagerou.glass/refrax",
                "X-Title": "Refrax",
            ],
            providerName: "OpenRouter",
        )
    }

    private static func makeCustomConfig(settings: BrowserSettings) -> OpenAIProviderConfig {
        // Fall back to a safe default if the user-provided URL doesn't parse.
        let baseURL = URL(string: settings.agentCustomBaseURL)
            ?? URL(string: "http://localhost:11434/v1")!
        let apiKey: String? = settings.agentCustomRequiresAuth
            ? AgentCredentialStore.loadAPIKey(for: .custom)
            : nil
        return OpenAIProviderConfig(
            baseURL: baseURL,
            apiKey: apiKey,
            extraHeaders: [:],
            providerName: "Custom (\(baseURL.host ?? "local"))",
        )
    }
}

/// The settings a chat client captures when it is built.
nonisolated struct AgentClientConfiguration: Equatable, Sendable {
    let provider: AgentProviderKind
    let model: String
    let maxTokens: Int
    let baseURL: String
    let requiresAuth: Bool
    let apiKeyHash: Int?
}
