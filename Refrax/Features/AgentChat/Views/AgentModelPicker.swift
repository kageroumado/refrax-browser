import Foundation
import SwiftUI

// MARK: - Model Entry

/// A model identifier plus optional metadata surfaced by the picker.
nonisolated struct AgentModelEntry: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let providerSlug: String?
    let contextLength: Int?
    let pricePromptPerMillion: Double?
    let priceCompletionPerMillion: Double?
    let supportsTools: Bool

    init(
        id: String,
        displayName: String? = nil,
        providerSlug: String? = nil,
        contextLength: Int? = nil,
        pricePromptPerMillion: Double? = nil,
        priceCompletionPerMillion: Double? = nil,
        supportsTools: Bool = true,
    ) {
        self.id = id
        self.displayName = displayName ?? id
        self.providerSlug = providerSlug
        self.contextLength = contextLength
        self.pricePromptPerMillion = pricePromptPerMillion
        self.priceCompletionPerMillion = priceCompletionPerMillion
        self.supportsTools = supportsTools
    }
}

// MARK: - Curated OpenAI Models

/// Static allowlist of known-good OpenAI models — `GET /v1/models` returns
/// hundreds of internal/deprecated identifiers, so we hand-curate the
/// picker. Users can still type a custom slug.
nonisolated enum AgentOpenAIModels {
    static let curated: [AgentModelEntry] = [
        .init(id: "gpt-5", displayName: "GPT-5", contextLength: 400_000),
        .init(id: "gpt-5-mini", displayName: "GPT-5 mini", contextLength: 400_000),
        .init(id: "gpt-4.1", displayName: "GPT-4.1", contextLength: 1_000_000),
        .init(id: "gpt-4.1-mini", displayName: "GPT-4.1 mini", contextLength: 1_000_000),
        .init(id: "o4-mini", displayName: "o4-mini (reasoning)", contextLength: 200_000),
        .init(id: "o3", displayName: "o3 (reasoning)", contextLength: 200_000),
        .init(id: "o3-mini", displayName: "o3-mini (reasoning)", contextLength: 200_000),
    ]
}

// MARK: - Remote Model Loader

/// Fetches `GET {base}/v1/models` for providers that expose it.
///
/// OpenRouter returns rich metadata (context length, pricing, supported
/// parameters); local servers typically return just `{id}`. The loader
/// caches results for the session to avoid hammering the endpoint.
@MainActor
@Observable
final class AgentModelLoader {
    private(set) var entries: [AgentModelEntry] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    private var hasLoaded = false

    /// Loads the model list for the given provider + config. Cached until
    /// the `AgentModelLoader` instance is discarded or ``invalidate()`` is
    /// called.
    func load(provider: AgentProviderKind, baseURL: URL, apiKey: String?, extraHeaders: [String: String]) async {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                loadError = "Invalid response"
                return
            }
            guard http.statusCode == 200 else {
                loadError = "HTTP \(http.statusCode)"
                return
            }
            let parsed = Self.parseModelList(data: data, provider: provider)
            entries = parsed
            hasLoaded = true
        } catch {
            loadError = error.localizedDescription
        }
    }

    func invalidate() {
        entries = []
        hasLoaded = false
        loadError = nil
    }

    /// Parses the JSON response from `GET /v1/models` into entries.
    ///
    /// Handles:
    /// - OpenRouter: rich objects with `context_length`, `pricing`, `supported_parameters`.
    /// - Ollama / LM Studio / OpenAI: plain `{id}` objects.
    static func parseModelList(data: Data, provider: AgentProviderKind) -> [AgentModelEntry] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let array: [[String: Any]] = if let list = json["data"] as? [[String: Any]] {
            list
        } else if let list = json["models"] as? [[String: Any]] {
            list
        } else {
            []
        }

        var out: [AgentModelEntry] = []
        for item in array {
            guard let id = item["id"] as? String ?? item["name"] as? String else { continue }

            let contextLength = item["context_length"] as? Int
            let pricing = item["pricing"] as? [String: Any]
            let promptPrice = (pricing?["prompt"] as? String).flatMap(Double.init) ?? (pricing?["prompt"] as? Double)
            let completionPrice = (pricing?["completion"] as? String).flatMap(Double.init)
                ?? (pricing?["completion"] as? Double)

            let supportedParams = item["supported_parameters"] as? [String] ?? []
            // If the endpoint advertises `supported_parameters`, trust it.
            // Otherwise assume tools are supported (local servers usually don't advertise).
            let supportsTools = supportedParams.isEmpty || supportedParams.contains("tools")

            let architecture = item["architecture"] as? [String: Any]
            let slug = architecture?["tokenizer"] as? String
                ?? (id.split(separator: "/").first.map(String.init))

            let nameField = item["name"] as? String
            let displayName = nameField ?? id

            out.append(.init(
                id: id,
                displayName: displayName,
                providerSlug: slug,
                contextLength: contextLength,
                pricePromptPerMillion: promptPrice.map { $0 * 1_000_000 },
                priceCompletionPerMillion: completionPrice.map { $0 * 1_000_000 },
                supportsTools: supportsTools,
            ))
        }

        // Filter to tool-capable models when the server tells us.
        let toolsOnly = out.filter(\.supportsTools)
        return toolsOnly.isEmpty ? out : toolsOnly
    }
}

// MARK: - Picker View

/// Liquid Glass-styled model picker surfaced by the agent settings sheet.
///
/// Behaviour varies by provider:
/// - **OpenAI**: shows ``AgentOpenAIModels/curated`` + a text field for
///   custom slugs.
/// - **OpenRouter**: fetches `/models`, filters to tool-capable entries,
///   groups by provider prefix, supports search.
/// - **Custom**: fetches `/models` from the user's base URL; falls back
///   to a plain text field if the endpoint isn't reachable.
struct AgentModelPicker: View {
    let provider: AgentProviderKind
    @Binding var selection: String
    let baseURL: URL?
    let apiKey: String?
    let extraHeaders: [String: String]

    @State private var loader = AgentModelLoader()
    @State private var searchText = ""
    @State private var showCustomField = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch provider {
            case .claudeAPI:
                claudePicker
            case .openAI:
                openAIPicker
            case .openRouter:
                remotePicker(groupedByProvider: true)
                    .task {
                        guard let baseURL else { return }
                        await loader.load(
                            provider: provider,
                            baseURL: baseURL,
                            apiKey: apiKey,
                            extraHeaders: extraHeaders,
                        )
                    }
            case .custom:
                remotePicker(groupedByProvider: false)
                    .task {
                        guard let baseURL else { return }
                        await loader.load(
                            provider: provider,
                            baseURL: baseURL,
                            apiKey: apiKey,
                            extraHeaders: extraHeaders,
                        )
                    }
            }
        }
    }

    // MARK: Claude

    private var claudePicker: some View {
        Picker("Model", selection: $selection) {
            ForEach(ClaudeModel.allCases, id: \.rawValue) { model in
                Text(model.displayName).tag(model.rawValue)
            }
        }
        .labelsHidden()
    }

    // MARK: OpenAI (curated)

    private var openAIPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Model", selection: Binding(
                get: { curatedSelection },
                set: { newValue in
                    if newValue == customSentinel {
                        showCustomField = true
                    } else {
                        showCustomField = false
                        selection = newValue
                    }
                },
            )) {
                ForEach(AgentOpenAIModels.curated) { entry in
                    HStack {
                        Text(entry.displayName)
                        if let ctx = entry.contextLength {
                            Text(Self.formatContext(ctx))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(entry.id)
                }
                Divider()
                Text("Custom slug…").tag(customSentinel)
            }
            .labelsHidden()

            if showCustomField || !AgentOpenAIModels.curated.map(\.id).contains(selection) {
                TextField("e.g., gpt-5-preview", text: $selection)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
            }
        }
    }

    private var curatedSelection: String {
        AgentOpenAIModels.curated.contains { $0.id == selection } ? selection : customSentinel
    }

    private let customSentinel = "__refrax_custom__"

    // MARK: Remote-fetched

    @ViewBuilder
    private func remotePicker(groupedByProvider: Bool) -> some View {
        if loader.isLoading {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading models…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let error = loader.loadError {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Model identifier", text: $selection)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                Text("Couldn't fetch models: \(error). Enter the identifier manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if loader.entries.isEmpty {
            TextField("Model identifier", text: $selection)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Search models…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)

                ScrollView {
                    if groupedByProvider {
                        groupedEntriesView
                    } else {
                        flatEntriesView
                    }
                }
                .frame(maxHeight: 240)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.background.secondary),
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 0.5),
                )
            }
        }
    }

    private var filteredEntries: [AgentModelEntry] {
        guard !searchText.isEmpty else { return loader.entries }
        let q = searchText.lowercased()
        return loader.entries.filter { entry in
            entry.id.lowercased().contains(q) || entry.displayName.lowercased().contains(q)
        }
    }

    private var flatEntriesView: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(filteredEntries) { entry in
                modelRow(entry)
                Divider()
            }
        }
    }

    private var groupedEntriesView: some View {
        let groups = Dictionary(grouping: filteredEntries) { entry -> String in
            if let slug = entry.id.split(separator: "/").first { String(slug) } else { "other" }
        }
        let sortedKeys = groups.keys.sorted()
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(sortedKeys, id: \.self) { key in
                Section {
                    ForEach(groups[key] ?? []) { entry in
                        modelRow(entry)
                        Divider()
                    }
                } header: {
                    Text(key.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.tertiary)
                }
            }
        }
    }

    private func modelRow(_ entry: AgentModelEntry) -> some View {
        Button {
            selection = entry.id
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.callout.weight(selection == entry.id ? .semibold : .regular))
                    HStack(spacing: 6) {
                        Text(entry.id)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        if let ctx = entry.contextLength {
                            Text("· \(Self.formatContext(ctx))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let p = entry.pricePromptPerMillion,
                           let c = entry.priceCompletionPerMillion {
                            Text("· $\(Self.formatPrice(p))/$\(Self.formatPrice(c))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 8)
                if selection == entry.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: Formatting

    private static func formatContext(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { "\(tokens / 1_000_000)M" }
        else if tokens >= 1_000 { "\(tokens / 1_000)K" }
        else { "\(tokens)" }
    }

    private static func formatPrice(_ perMillion: Double) -> String {
        if perMillion >= 1 { String(format: "%.2f", perMillion) }
        else { String(format: "%.3f", perMillion) }
    }
}
