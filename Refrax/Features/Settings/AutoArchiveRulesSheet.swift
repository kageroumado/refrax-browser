import SwiftData
import SwiftUI

// MARK: - Auto Archive Rules Sheet

/// Sheet for managing auto-archive rules.
///
/// Displays a list of user-defined rules with options to add, edit, enable/disable,
/// and delete rules. Also provides a "Run Now" button to trigger immediate rule execution.
struct AutoArchiveRulesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(BrowserState.self) private var state
    @Environment(ScheduledTasksManager.self) private var scheduledTasksManager
    @Environment(TabAutoArchiveManager.self) private var autoArchiveManager

    @State private var rules: [ArchiveRule] = []
    @State private var showAddSheet = false
    @State private var ruleToEdit: ArchiveRule?
    @State private var isRunning = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    if rules.isEmpty {
                        // Empty state handled separately
                    } else {
                        ForEach(rules) { rule in
                            ArchiveRuleRow(
                                rule: rule,
                                spaceName: spaceName(for: rule.spaceID),
                                onEdit: { ruleToEdit = rule },
                                onDelete: { deleteRule(rule) },
                            )
                        }
                    }
                }
                .overlay {
                    if rules.isEmpty {
                        ContentUnavailableView {
                            Label("No Auto-Archive Rules", systemImage: "archivebox")
                        } description: {
                            Text("Create rules to automatically archive tabs based on inactivity or tab count limits.")
                        } actions: {
                            Button("Add Rule") {
                                showAddSheet = true
                            }
                        }
                    }
                }

                // Bottom bar with status and Run Now
                statusBar
            }
            .navigationTitle("Auto-Archive Rules")
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
        .onAppear(perform: fetchRules)
        .sheet(isPresented: $showAddSheet, onDismiss: fetchRules) {
            AddEditArchiveRuleSheet(rule: nil)
        }
        .sheet(item: $ruleToEdit, onDismiss: fetchRules) { rule in
            AddEditArchiveRuleSheet(rule: rule)
        }
    }

    private var statusBar: some View {
        HStack {
            // Last check status
            if let lastRun = scheduledTasksManager.lastTaskRun {
                Text("Last check: \(lastRun.relativeFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not yet checked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Run Now button
            Button {
                Task {
                    await runNow()
                }
            } label: {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 8)
                } else {
                    Text("Run Now")
                }
            }
            .disabled(isRunning || rules.isEmpty)
        }
        .padding()
        .background(.regularMaterial)
    }

    // MARK: - Data

    private func fetchRules() {
        let descriptor = FetchDescriptor<ArchiveRule>(
            sortBy: [SortDescriptor(\.priority, order: .reverse), SortDescriptor(\.name)],
        )

        do {
            rules = try modelContext.fetch(descriptor)
        } catch {
            Logger.error("Failed to fetch archive rules: \(error)", category: Logger.tabs)
            rules = []
        }
    }

    private func deleteRule(_ rule: ArchiveRule) {
        modelContext.delete(rule)
        try? modelContext.save()
        fetchRules()
    }

    private func spaceName(for spaceID: UUID?) -> String? {
        guard let spaceID else { return nil }
        return state.spaces.first(where: { $0.id == spaceID })?.name
    }

    private func runNow() async {
        isRunning = true
        await scheduledTasksManager.runNow()
        isRunning = false
    }
}

// MARK: - Archive Rule Row

private struct ArchiveRuleRow: View {
    @Bindable var rule: ArchiveRule
    let spaceName: String?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: $rule.isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.headline)
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)

                HStack(spacing: 4) {
                    if let spaceName {
                        Text(spaceName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Text(rule.ruleDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Edit") {
                onEdit()
            }
            .buttonStyle(.borderless)

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
    }
}
