import SwiftData
import SwiftUI

// MARK: - Add/Edit Archive Rule Sheet

/// Sheet for creating or editing an auto-archive rule.
///
/// When `rule` is nil, creates a new rule. When `rule` is provided, edits the existing rule.
struct AddEditArchiveRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(BrowserState.self) private var state

    /// The rule to edit, or nil to create a new rule.
    let rule: ArchiveRule?

    // MARK: - Form State

    @State private var name: String = ""
    @State private var ruleType: ArchiveRuleType = .inactivity
    @State private var domainPattern: String = ""
    @State private var selectedSpaceID: UUID?
    @State private var inactivityDays: Int = 3
    @State private var maxTabCount: Int = 50
    @State private var priority: Int = 0

    private var isEditing: Bool {
        rule != nil
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Basic Info

                Section {
                    TextField("Rule Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Name")
                } footer: {
                    Text("A descriptive name for this rule.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: - Rule Type

                Section {
                    Picker("Rule Type", selection: $ruleType) {
                        ForEach(ArchiveRuleType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(ruleType.typeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Type")
                }

                // MARK: - Type-Specific Settings

                Section {
                    switch ruleType {
                    case .inactivity:
                        inactivitySettings
                    case .tabCountLimit:
                        tabCountSettings
                    }
                } header: {
                    Text("Criteria")
                }

                // MARK: - Scope

                Section {
                    TextField("Domain Pattern", text: $domainPattern)
                        .textFieldStyle(.roundedBorder)

                    Picker("Space", selection: $selectedSpaceID) {
                        Text("All Spaces").tag(nil as UUID?)
                        ForEach(state.spaces, id: \.id) { space in
                            Text(space.name).tag(space.id as UUID?)
                        }
                    }
                } header: {
                    Text("Scope")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Domain pattern examples:")
                        Text("• *.reddit.com — matches reddit.com and all subdomains")
                        Text("• example.com — matches only example.com")
                        Text("• Leave empty to match all domains")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                // MARK: - Advanced

                Section {
                    Stepper("Priority: \(priority)", value: $priority, in: 0 ... 100)
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Higher priority rules are evaluated first. Use this to ensure specific rules take precedence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Rule" : "Add Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        saveRule()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear(perform: loadRuleIfEditing)
        }
        .frame(minWidth: 450, minHeight: 500)
    }

    // MARK: - Inactivity Settings

    private var inactivitySettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(
                "Archive after \(inactivityDays) \(inactivityDays == 1 ? "day" : "days") of inactivity",
                value: $inactivityDays,
                in: 1 ... 365,
            )

            // Quick presets
            HStack(spacing: 8) {
                Text("Quick set:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach([1, 3, 7, 14, 30], id: \.self) { days in
                    Button("\(days)d") {
                        inactivityDays = days
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Tab Count Settings

    private var tabCountSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(
                "Archive oldest when exceeding \(maxTabCount) tabs",
                value: $maxTabCount,
                in: 5 ... 500,
                step: 5,
            )

            // Quick presets
            HStack(spacing: 8) {
                Text("Quick set:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach([10, 20, 50, 100], id: \.self) { count in
                    Button("\(count)") {
                        maxTabCount = count
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadRuleIfEditing() {
        guard let rule else { return }

        name = rule.name
        ruleType = rule.ruleType
        domainPattern = rule.domainPattern ?? ""
        selectedSpaceID = rule.spaceID
        inactivityDays = rule.inactivityDays ?? 3
        maxTabCount = rule.maxTabCount ?? 50
        priority = rule.priority
    }

    private func saveRule() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDomain = domainPattern.trimmingCharacters(in: .whitespacesAndNewlines)

        if let rule {
            // Update existing rule
            rule.name = trimmedName
            rule.ruleType = ruleType
            rule.domainPattern = trimmedDomain.isEmpty ? nil : trimmedDomain
            rule.spaceID = selectedSpaceID
            rule.inactivityDays = ruleType == .inactivity ? inactivityDays : nil
            rule.maxTabCount = ruleType == .tabCountLimit ? maxTabCount : nil
            rule.priority = priority
        } else {
            // Create new rule
            let newRule = ArchiveRule(
                name: trimmedName,
                ruleType: ruleType,
                domainPattern: trimmedDomain.isEmpty ? nil : trimmedDomain,
                isEnabled: true,
                priority: priority,
                spaceID: selectedSpaceID,
                inactivityDays: ruleType == .inactivity ? inactivityDays : nil,
                maxTabCount: ruleType == .tabCountLimit ? maxTabCount : nil,
            )
            modelContext.insert(newRule)
        }

        try? modelContext.save()
    }
}
