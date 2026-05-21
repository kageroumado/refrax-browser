import SwiftUI

// MARK: - Search Settings

struct SearchSettingsView: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(CustomSearchEngineManager.self) private var customSearchEngineManager
    let highlightedItemId: String?

    @State private var editingEngine: EditingEngine?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Default search engine", selection: $settings.defaultSearchEngine) {
                    ForEach(SearchEngine.builtIns, id: \.id) { engine in
                        Text(engine.name).tag(engine)
                    }

                    if !customSearchEngineManager.cachedEngines.isEmpty {
                        Divider()

                        ForEach(customSearchEngineManager.cachedEngines, id: \.id) { engine in
                            Text(engine.name).tag(engine)
                        }
                    }
                }
                .highlightable(id: "search.engine", highlightedItemId: highlightedItemId)
            } header: {
                Text("Default Search Engine")
            } footer: {
                Text("Type an engine's abbreviation (like \"g\" or \"ddg\") and press Tab to use it for a single search.")
            }

            Section {
                customEnginesList

                Button("Add Custom Search Engine...") {
                    editingEngine = .add
                }
            } header: {
                Text("Custom Search Engines")
            } footer: {
                Text("Custom engines appear in Command Lens. Type the alias and press Tab to activate.")
            }
            .highlightable(id: "search.custom", highlightedItemId: highlightedItemId)
        }
        .formStyle(.grouped)
        .sheet(item: $editingEngine) { engine in
            CustomSearchEngineEditSheet(
                engineID: engine.engineID,
                customSearchEngineManager: customSearchEngineManager,
            )
        }
    }

    /// Wrapper to drive `.sheet(item:)` — ensures the sheet content
    /// is recreated with the correct engine ID on each presentation.
    private enum EditingEngine: Identifiable {
        case add
        case edit(UUID)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let uuid): uuid.uuidString
            }
        }

        var engineID: UUID? {
            switch self {
            case .add: nil
            case .edit(let uuid): uuid
            }
        }
    }

    // MARK: - Custom Engines List

    @ViewBuilder
    private var customEnginesList: some View {
        let engines = customSearchEngineManager.allModels()

        if engines.isEmpty {
            Text("No custom search engines. Add one below, or browse sites with search to auto-detect them.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(engines, id: \.id) { engine in
                HStack(spacing: 12) {
                    Image(systemName: engine.iconName)
                        .frame(width: 20)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(engine.name)
                                .fontWeight(.medium)

                            Text("(\(engine.alias))")
                                .foregroundStyle(.secondary)

                            if engine.isAutoDetected {
                                Text("Auto-detected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }

                        Text(engine.searchURLTemplate)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        editingEngine = .edit(engine.id)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)

                    Button(role: .destructive) {
                        customSearchEngineManager.delete(id: engine.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Edit Sheet

private struct CustomSearchEngineEditSheet: View {
    let engineID: UUID?
    let customSearchEngineManager: CustomSearchEngineManager

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var name = ""
    @State private var alias = ""
    @State private var searchURLTemplate = ""
    @State private var suggestionURLTemplate = ""

    private var isEditing: Bool {
        engineID != nil
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !alias.trimmingCharacters(in: .whitespaces).isEmpty
            && !searchURLTemplate.trimmingCharacters(in: .whitespaces).isEmpty
            && searchURLTemplate.contains("%@")
    }

    private var aliasConflict: Bool {
        let trimmed = alias.lowercased().trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // When editing, the engine's own alias is not a conflict
        if let engineID,
           let existing = customSearchEngineManager.allModels().first(where: { $0.id == engineID }),
           existing.alias == trimmed {
            return false
        }

        return customSearchEngineManager.aliasExists(trimmed)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("YouTube"))
                    TextField("Alias", text: $alias, prompt: Text("yt"))
                        .textCase(.lowercase)
                        .onChange(of: alias) { _, newValue in
                            alias = newValue.lowercased()
                        }

                    if aliasConflict {
                        Text("This alias is already in use.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    TextField(
                        "Search URL Template",
                        text: $searchURLTemplate,
                        prompt: Text("https://www.youtube.com/results?search_query=%@"),
                    )
                    .textContentType(.URL)

                    TextField(
                        "Suggestion URL (optional)",
                        text: $suggestionURLTemplate,
                        prompt: Text("https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&q=%@"),
                    )
                    .textContentType(.URL)
                } header: {
                    Text("URL Templates")
                } footer: {
                    Text("Use %@ as the placeholder for the search query.")
                }

                Section {
                    Button("Test Search URL") {
                        let testURL = searchURLTemplate.replacingOccurrences(of: "%@", with: "test")
                        if let url = URL(string: testURL) {
                            openURL(url)
                        }
                    }
                    .disabled(searchURLTemplate.isEmpty || !searchURLTemplate.contains("%@"))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isEditing ? "Save" : "Add") {
                    saveEngine()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || aliasConflict)
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 360)
        .onAppear {
            loadExistingEngine()
        }
    }

    private func loadExistingEngine() {
        guard let engineID,
              let engine = customSearchEngineManager.allModels().first(where: { $0.id == engineID })
        else { return }

        name = engine.name
        alias = engine.alias
        searchURLTemplate = engine.searchURLTemplate
        suggestionURLTemplate = engine.suggestionURLTemplate ?? ""
    }

    private func saveEngine() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedAlias = alias.lowercased().trimmingCharacters(in: .whitespaces)
        let trimmedSearch = searchURLTemplate.trimmingCharacters(in: .whitespaces)
        let trimmedSuggestion = suggestionURLTemplate.trimmingCharacters(in: .whitespaces)
        let suggestion: String? = trimmedSuggestion.isEmpty ? nil : trimmedSuggestion

        if let engineID {
            customSearchEngineManager.update(
                id: engineID,
                name: trimmedName,
                alias: trimmedAlias,
                searchURLTemplate: trimmedSearch,
                suggestionURLTemplate: suggestion,
            )
        } else {
            customSearchEngineManager.add(
                name: trimmedName,
                alias: trimmedAlias,
                searchURLTemplate: trimmedSearch,
                suggestionURLTemplate: suggestion,
            )
        }
    }
}
