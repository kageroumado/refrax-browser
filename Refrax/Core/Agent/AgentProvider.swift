import Foundation

/// Which backend provides the agent chat functionality.
nonisolated enum AgentProviderKind: String, Codable, Sendable, CaseIterable {
    /// Direct Anthropic Messages API (API key).
    ///
    /// Raw value is preserved as `"claudeDirect"` for backward compatibility
    /// with persisted settings from earlier releases. See ``init(from:)`` for
    /// migration of legacy values such as `"openClaw"`.
    case claudeAPI = "claudeDirect"

    /// OpenAI Chat Completions API (api.openai.com).
    case openAI

    /// OpenRouter aggregator (openrouter.ai). Routes to many model providers.
    case openRouter

    /// Any OpenAI-compatible endpoint (local: Ollama, LM Studio, llama.cpp; or any other).
    case custom

    var displayName: String {
        switch self {
        case .claudeAPI: "Claude"
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .custom: "Custom (OpenAI-compatible)"
        }
    }

    /// Short label suited for picker chrome.
    var shortLabel: String {
        switch self {
        case .claudeAPI: "Claude"
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .custom: "Custom"
        }
    }

    /// Whether this provider speaks the OpenAI Chat Completions wire format.
    var isOpenAIWireFormat: Bool {
        switch self {
        case .claudeAPI: false
        case .openAI, .openRouter, .custom: true
        }
    }

    /// Decodes the provider kind, migrating unknown or legacy values to ``claudeAPI``.
    ///
    /// Used to silently migrate users persisted with the removed `.openClaw`
    /// case (or any future unknown value) without crashing on decode.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = AgentProviderKind(rawValue: raw) ?? .claudeAPI
    }
}

/// Known Claude model identifiers with display metadata.
nonisolated enum ClaudeModel: String, CaseIterable, Sendable {
    case opus = "claude-opus-4-6"
    case sonnet = "claude-sonnet-4-5-20250929"
    case haiku = "claude-haiku-4-5-20251001"

    var displayName: String {
        switch self {
        case .opus: "Claude Opus 4.6"
        case .sonnet: "Claude Sonnet 4.5"
        case .haiku: "Claude Haiku 4.5"
        }
    }

    var contextWindow: Int {
        200_000
    }
}
