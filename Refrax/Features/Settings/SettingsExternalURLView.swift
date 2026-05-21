import SwiftUI

/// Settings view for configuring external URL handling.
///
/// Controls how Refrax handles URLs opened from other applications,
/// including default behavior, URL-specific rules, and source app rules.
struct ExternalURLSettingsView: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(TabManager.self) private var tabManager

    let highlightedItemId: String?

    @State private var showURLRulesSheet = false
    @State private var showSourceAppRulesSheet = false

    private var externalSettings: ExternalURLSettings {
        settings.privacyProtection.externalURLSettings
    }

    var body: some View {
        Group {
            Section {
                Toggle(
                    "Enable custom external URL handling",
                    isOn: Binding(
                        get: { externalSettings.enableCustomHandling },
                        set: { externalSettings.enableCustomHandling = $0 },
                    ),
                )
                .highlightable(id: "external.enable", highlightedItemId: highlightedItemId)

                if externalSettings.enableCustomHandling {
                    Picker(
                        "Default behavior",
                        selection: Binding(
                            get: { externalSettings.defaultBehavior },
                            set: { externalSettings.defaultBehavior = $0 },
                        ),
                    ) {
                        ForEach(ExternalURLBehavior.allCases, id: \.self) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                    .highlightable(id: "external.defaultBehavior", highlightedItemId: highlightedItemId)

                    if externalSettings.defaultBehavior == .openInSpecificSpace {
                        spacePicker
                    }

                    Toggle(
                        "Activate Refrax when receiving URLs",
                        isOn: Binding(
                            get: { externalSettings.activateOnExternalURL },
                            set: { externalSettings.activateOnExternalURL = $0 },
                        ),
                    )
                    .highlightable(id: "external.activate", highlightedItemId: highlightedItemId)

                    if !externalSettings.activateOnExternalURL {
                        Toggle(
                            "Show notification for background opens",
                            isOn: Binding(
                                get: { externalSettings.notifyOnBackgroundOpen },
                                set: { externalSettings.notifyOnBackgroundOpen = $0 },
                            ),
                        )
                        .highlightable(id: "external.notify", highlightedItemId: highlightedItemId)
                    }

                    HStack {
                        VStack(alignment: .leading) {
                            Text("URL Rules")
                            Text("\(externalSettings.rules.count) rule\(externalSettings.rules.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit…") {
                            showURLRulesSheet = true
                        }
                    }
                    .highlightable(id: "external.urlRules", highlightedItemId: highlightedItemId)

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Source App Rules")
                            Text("\(externalSettings.sourceAppRules.count) rule\(externalSettings.sourceAppRules.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit…") {
                            showSourceAppRulesSheet = true
                        }
                    }
                    .highlightable(id: "external.sourceAppRules", highlightedItemId: highlightedItemId)
                }
            } header: {
                Text("External URLs")
            } footer: {
                Text("Customize how URLs opened from other apps are handled. Rules match by domain pattern or source application.")
            }
        }
        .sheet(isPresented: $showURLRulesSheet) {
            ExternalURLRulesSheet()
        }
        .sheet(isPresented: $showSourceAppRulesSheet) {
            SourceAppRulesSheet()
        }
    }

    private var spacePicker: some View {
        Picker(
            "Target space:",
            selection: Binding(
                get: { externalSettings.defaultTargetSpaceID },
                set: { externalSettings.defaultTargetSpaceID = $0 },
            ),
        ) {
            Text("None").tag(nil as UUID?)
            ForEach(tabManager.state.spaces) { space in
                Text(space.name).tag(space.id as UUID?)
            }
        }
        .highlightable(id: "external.targetSpace", highlightedItemId: highlightedItemId)
    }
}

// MARK: - URL Rules Sheet

private struct ExternalURLRulesSheet: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var showAddSheet = false

    private var externalSettings: ExternalURLSettings {
        settings.privacyProtection.externalURLSettings
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(externalSettings.rules.sorted(by: { $0.order < $1.order })) { rule in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(rule.name)
                                .font(.headline)
                            Text(rule.patternDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(rule.actionDescription)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Toggle("", isOn: Binding(
                            get: { rule.isEnabled },
                            set: { rule.isEnabled = $0 },
                        ))
                        .labelsHidden()
                    }
                }
                .onDelete(perform: deleteRules)
            }
            .overlay {
                if externalSettings.rules.isEmpty {
                    ContentUnavailableView {
                        Label("No URL Rules", systemImage: "link")
                    } description: {
                        Text("Add rules to customize handling for specific URL patterns.")
                    } actions: {
                        Button("Add Rule") {
                            showAddSheet = true
                        }
                    }
                }
            }
            .navigationTitle("External URL Rules")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .sheet(isPresented: $showAddSheet) {
            AddExternalURLRuleSheet()
        }
    }

    private func deleteRules(at offsets: IndexSet) {
        let sorted = externalSettings.rules.sorted(by: { $0.order < $1.order })
        for index in offsets {
            if let idx = externalSettings.rules.firstIndex(where: { $0.id == sorted[index].id }) {
                externalSettings.rules.remove(at: idx)
            }
        }
    }
}

// MARK: - Add URL Rule Sheet

private struct AddExternalURLRuleSheet: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(TabManager.self) private var tabManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var domainPattern = ""
    @State private var pathPattern = ""
    @State private var actionType: ActionType = .currentSpace
    @State private var targetSpaceID: UUID?

    private var externalSettings: ExternalURLSettings {
        settings.privacyProtection.externalURLSettings
    }

    private var isValid: Bool {
        !name.isEmpty && !domainPattern.isEmpty
    }

    enum ActionType: String, CaseIterable {
        case currentSpace = "Current Space"
        case glimpse = "Glimpse"
        case specificSpace = "Specific Space"
        case block = "Block"

        var action: ExternalURLAction {
            switch self {
            case .currentSpace: .openInCurrentSpace
            case .glimpse: .openInGlimpse
            case .specificSpace: .openInCurrentSpace // Will be overridden
            case .block: .block
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                Section {
                    TextField("Domain Pattern", text: $domainPattern)
                        .textFieldStyle(.roundedBorder)
                    Text("Use * for wildcards. Example: *.github.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Path Pattern (optional)", text: $pathPattern)
                        .textFieldStyle(.roundedBorder)
                    Text("Example: /repos/*")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Action", selection: $actionType) {
                        ForEach(ActionType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    if actionType == .specificSpace {
                        Picker("Target Space", selection: $targetSpaceID) {
                            Text("Select…").tag(nil as UUID?)
                            ForEach(tabManager.state.spaces) { space in
                                Text(space.name).tag(space.id as UUID?)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add URL Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addRule()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 350)
    }

    private func addRule() {
        var action = actionType.action
        if actionType == .specificSpace, let spaceID = targetSpaceID {
            action = .openInSpace(spaceID)
        }

        let rule = ExternalURLRule(
            name: name,
            domainPattern: domainPattern,
            pathPattern: pathPattern.isEmpty ? nil : pathPattern,
            action: action,
            targetSpaceID: targetSpaceID,
            order: externalSettings.rules.count,
        )
        externalSettings.rules.append(rule)
    }
}

// MARK: - Source App Rules Sheet

private struct SourceAppRulesSheet: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var showAddSheet = false

    private var externalSettings: ExternalURLSettings {
        settings.privacyProtection.externalURLSettings
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(externalSettings.sourceAppRules.sorted(by: { $0.order < $1.order })) { rule in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(rule.name)
                                .font(.headline)
                            Text(rule.bundleIDPattern)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(rule.actionDescription)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Toggle("", isOn: Binding(
                            get: { rule.isEnabled },
                            set: { rule.isEnabled = $0 },
                        ))
                        .labelsHidden()
                    }
                }
                .onDelete(perform: deleteRules)
            }
            .overlay {
                if externalSettings.sourceAppRules.isEmpty {
                    ContentUnavailableView {
                        Label("No Source App Rules", systemImage: "app.badge")
                    } description: {
                        Text("Add rules to customize handling based on which app opened the URL.")
                    } actions: {
                        Button("Add Rule") {
                            showAddSheet = true
                        }
                    }
                }
            }
            .navigationTitle("Source App Rules")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .sheet(isPresented: $showAddSheet) {
            AddSourceAppRuleSheet()
        }
    }

    private func deleteRules(at offsets: IndexSet) {
        let sorted = externalSettings.sourceAppRules.sorted(by: { $0.order < $1.order })
        for index in offsets {
            if let idx = externalSettings.sourceAppRules.firstIndex(where: { $0.id == sorted[index].id }) {
                externalSettings.sourceAppRules.remove(at: idx)
            }
        }
    }
}

// MARK: - Add Source App Rule Sheet

private struct AddSourceAppRuleSheet: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(TabManager.self) private var tabManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var bundleIDPattern = ""
    @State private var actionType: AddExternalURLRuleSheet.ActionType = .currentSpace
    @State private var targetSpaceID: UUID?

    private var externalSettings: ExternalURLSettings {
        settings.privacyProtection.externalURLSettings
    }

    private var isValid: Bool {
        !name.isEmpty && !bundleIDPattern.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                Section {
                    TextField("Bundle ID Pattern", text: $bundleIDPattern)
                        .textFieldStyle(.roundedBorder)
                    Text("Use * for wildcards. Example: com.apple.*")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Common apps:")
                            .foregroundStyle(.secondary)
                        Picker("", selection: $bundleIDPattern) {
                            Text("Select…").tag("")
                            ForEach(SourceAppRule.CommonApps.all, id: \.bundleID) { app in
                                Text(app.name).tag(app.bundleID)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: bundleIDPattern) { _, newValue in
                            if let match = SourceAppRule.CommonApps.all.first(where: { $0.bundleID == newValue }) {
                                if name.isEmpty {
                                    name = "Links from \(match.name)"
                                }
                            }
                        }
                    }
                }

                Section {
                    Picker("Action", selection: $actionType) {
                        ForEach(AddExternalURLRuleSheet.ActionType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    if actionType == .specificSpace {
                        Picker("Target Space", selection: $targetSpaceID) {
                            Text("Select…").tag(nil as UUID?)
                            ForEach(tabManager.state.spaces) { space in
                                Text(space.name).tag(space.id as UUID?)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Source App Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addRule()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }

    private func addRule() {
        var action = actionType.action
        if actionType == .specificSpace, let spaceID = targetSpaceID {
            action = .openInSpace(spaceID)
        }

        let rule = SourceAppRule(
            name: name,
            bundleIDPattern: bundleIDPattern,
            action: action,
            targetSpaceID: targetSpaceID,
            order: externalSettings.sourceAppRules.count,
        )
        externalSettings.sourceAppRules.append(rule)
    }
}
