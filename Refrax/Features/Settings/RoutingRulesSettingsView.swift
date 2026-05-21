import SwiftData
import SwiftUI

/// Settings view for managing URL routing rules.
///
/// Routing rules automatically direct URLs to specific destinations based on
/// conditions like domain, time of day, or source application.
///
/// ## Integration
///
/// Add this view to the Privacy settings section or as a dedicated category.
/// The view manages its own SwiftData queries and rule editing.
struct RoutingRulesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RoutingRule.priority, order: .reverse) private var rules: [RoutingRule]

    @State private var selectedRule: RoutingRule?
    @State private var showingNewRuleSheet = false
    @State private var showingTestPanel = false
    @State private var testURL = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            rulesList
            footerButtons
        }
        .padding()
        .sheet(isPresented: $showingNewRuleSheet) {
            RuleEditorSheet(rule: nil) { newRule in
                modelContext.insert(newRule)
            }
        }
        .sheet(item: $selectedRule) { rule in
            RuleEditorSheet(rule: rule) { _ in
                rule.markModified()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("URL Routing Rules")
                .font(.headline)

            Text("Automatically direct URLs to specific spaces, groups, or Glimpse windows based on conditions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Rules List

    private var rulesList: some View {
        Group {
            if rules.isEmpty {
                emptyState
            } else {
                List(selection: $selectedRule) {
                    ForEach(rules) { rule in
                        RuleRowView(rule: rule)
                            .tag(rule)
                    }
                    .onDelete(perform: deleteRules)
                    .onMove(perform: moveRules)
                }
                .listStyle(.bordered)
                .frame(minHeight: 200)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)

            Text("No Routing Rules")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Create rules to automatically route URLs to specific destinations.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Footer

    private var footerButtons: some View {
        HStack {
            Button {
                showingNewRuleSheet = true
            } label: {
                Label("Add Rule", systemImage: "plus")
            }

            Spacer()

            if !rules.isEmpty {
                Button("Test URL...") {
                    showingTestPanel = true
                }
                .popover(isPresented: $showingTestPanel, arrowEdge: .bottom) {
                    testURLPanel
                }
            }
        }
    }

    // MARK: - Test Panel

    private var testURLPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test URL")
                .font(.headline)

            TextField("Enter URL to test", text: $testURL)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            if let url = URL(string: testURL), !testURL.isEmpty {
                testResult(for: url)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func testResult(for url: URL) -> some View {
        let context = NavigationContext(url: url)
        let matchingRules = rules.filter { $0.matches(context) }

        if let firstMatch = matchingRules.first {
            VStack(alignment: .leading, spacing: 4) {
                Label("Matches: \(firstMatch.name)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Text(firstMatch.action.displayDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("No matching rules", systemImage: "xmark.circle")
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Actions

    private func deleteRules(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(rules[index])
        }
    }

    private func moveRules(from source: IndexSet, to destination: Int) {
        var rulesCopy = rules
        rulesCopy.move(fromOffsets: source, toOffset: destination)

        // Update priorities based on new positions
        for (index, rule) in rulesCopy.enumerated() {
            rule.priority = rulesCopy.count - index
            rule.markModified()
        }
    }
}

// MARK: - Rule Row View

private struct RuleRowView: View {
    let rule: RoutingRule

    var body: some View {
        HStack(spacing: 12) {
            // Enable toggle
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { rule.isEnabled = $0; rule.markModified() },
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            // Rule info
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.body)
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)

                HStack(spacing: 8) {
                    Text("\(rule.conditions.count) condition\(rule.conditions.count == 1 ? "" : "s")")
                    Text("→")
                    Text(rule.action.typeLabel)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Priority indicator
            Text("Priority: \(rule.priority)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Rule Editor Sheet

struct RuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let rule: RoutingRule?
    let onSave: (RoutingRule) -> Void

    @State private var name: String = ""
    @State private var isEnabled: Bool = true
    @State private var priority: Int = 0
    @State private var conditions: [RoutingCondition] = []
    @State private var action: RoutingAction = .openInGlimpse

    init(rule: RoutingRule?, onSave: @escaping (RoutingRule) -> Void) {
        self.rule = rule
        self.onSave = onSave

        if let rule {
            _name = State(initialValue: rule.name)
            _isEnabled = State(initialValue: rule.isEnabled)
            _priority = State(initialValue: rule.priority)
            _conditions = State(initialValue: rule.conditions)
            _action = State(initialValue: rule.action)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(rule == nil ? "New Routing Rule" : "Edit Routing Rule")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Rule Settings") {
                    TextField("Name", text: $name)
                    Toggle("Enabled", isOn: $isEnabled)
                    Stepper("Priority: \(priority)", value: $priority, in: 0 ... 100)
                }

                Section("Conditions") {
                    if conditions.isEmpty {
                        Text("No conditions - rule will match all URLs")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(conditions.enumerated()), id: \.offset) { index, condition in
                            HStack {
                                Text(condition.displayDescription)
                                Spacer()
                                Button {
                                    conditions.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Menu("Add Condition") {
                        Button("Domain Pattern...") { addDomainCondition() }
                        Button("Path Pattern...") { addPathCondition() }
                        Divider()
                        Button("Weekday Only") { conditions.append(.dayOfWeek(.weekday)) }
                        Button("Weekend Only") { conditions.append(.dayOfWeek(.weekend)) }
                    }
                }

                Section("Action") {
                    Picker("Action Type", selection: $action) {
                        Text("Open in Glimpse").tag(RoutingAction.openInGlimpse)
                        Text("Block").tag(RoutingAction.block)
                    }
                    .pickerStyle(.inline)
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Save") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 500)
    }

    // MARK: - Condition Helpers

    @State private var pendingPattern = ""

    private func addDomainCondition() {
        // In a full implementation, this would show a text input
        // For now, add a placeholder
        conditions.append(.domain("*.example.com"))
    }

    private func addPathCondition() {
        conditions.append(.path("/path/*"))
    }

    // MARK: - Save

    private func save() {
        if let rule {
            // Update existing rule
            rule.name = name
            rule.isEnabled = isEnabled
            rule.priority = priority
            rule.conditions = conditions
            rule.action = action
            rule.markModified()
            onSave(rule)
        } else {
            // Create new rule
            let newRule = RoutingRule(
                name: name,
                conditions: conditions,
                action: action,
                priority: priority,
                isEnabled: isEnabled,
            )
            onSave(newRule)
        }
    }
}
