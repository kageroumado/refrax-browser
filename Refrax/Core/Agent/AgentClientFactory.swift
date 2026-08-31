import Foundation

/// Creates the appropriate agent chat client based on user settings.
nonisolated enum AgentClientFactory {
    /// Returns a new chat client configured for the user's chosen agent provider.
    @MainActor
    static func makeClient(settings: BrowserSettings) -> any AgentChatClientProtocol {
        switch settings.agentProviderKind {
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
