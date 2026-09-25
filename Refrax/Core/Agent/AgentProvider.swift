import Foundation

/// Which backend provides the agent chat functionality.
nonisolated enum AgentProviderKind: String, Codable, Sendable, CaseIterable {
    /// The locally installed Claude Code CLI (`claude -p`), signed in with the user's own login.
    case claudeCode

    /// The locally installed Codex CLI (`codex exec`), signed in with the user's own login.
    case codex

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
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .claudeAPI: "Claude API"
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .custom: "Custom (OpenAI-compatible)"
        }
    }

    /// Short label suited for picker chrome.
    var shortLabel: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .claudeAPI: "Claude API"
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .custom: "Custom"
        }
    }

    /// The local CLI that runs the agent, for providers that drive one.
    var cliRuntime: CLIAgentRuntime? {
        switch self {
        case .claudeCode: .claudeCode
        case .codex: .codex
        case .claudeAPI, .openAI, .openRouter, .custom: nil
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
///
/// The picker also accepts any other identifier as a custom slug.
nonisolated enum ClaudeModel: String, CaseIterable, Sendable {
    case fable = "claude-fable-5-1"
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5"
    case haiku = "claude-haiku-4-5-20251001"

    var displayName: String {
        switch self {
        case .fable: "Claude Fable 5.1"
        case .opus: "Claude Opus 5.5"
        case .sonnet: "Claude Sonnet 5"
        case .haiku: "Claude Haiku 4.5"
        }
    }

    /// Identifiers the picker offered in earlier releases that the API has retired.
    static let retiredIdentifiers: Set<String> = [
        "claude-opus-4-6",
        "claude-sonnet-4-5-20250929",
    ]

    /// Maps a persisted identifier onto a live one: retired and empty
    /// identifiers become ``sonnet``; everything else passes through, so
    /// custom slugs survive.
    static func migrated(_ identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || retiredIdentifiers.contains(trimmed) {
            return sonnet.rawValue
        }
        return trimmed
    }
}
