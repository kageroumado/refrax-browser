import SwiftUI

/// Settings view for managing all configured domain time limits.
///
/// Displays a table of all domains with time limits showing:
/// - Domain name
/// - Daily limit duration
/// - Time spent today
/// - Status (OK, Warning, Exceeded)
///
/// Users can add new limits, edit existing ones, or remove limits.
struct TimeLimitsSettingsView: View {
    @Environment(BrowserState.self) private var browserState
    @Environment(\.dismiss) private var dismiss

    @State private var limits: [DomainTimeLimitData] = []
    @State private var timeSpentCache: [String: TimeInterval] = [:]
    @State private var showAddSheet = false
    @State private var editingLimit: DomainTimeLimitData?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 500, minHeight: 400)
        .task { await refreshLimits() }
        .sheet(isPresented: $showAddSheet) {
            AddTimeLimitSheet { Task { await refreshLimits() } }
        }
        .sheet(item: $editingLimit) { limit in
            EditTimeLimitSheet(limit: limit) { Task { await refreshLimits() } }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Time Limits")
                .font(.headline)

            Spacer()

            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if limits.isEmpty {
            ContentUnavailableView {
                Label("No Time Limits", systemImage: "timer")
            } description: {
                Text("Add daily time limits for specific websites to manage your browsing time.")
            } actions: {
                Button("Add Time Limit") {
                    showAddSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(limits, id: \.domain) { limit in
                    TimeLimitRow(
                        limit: limit,
                        timeSpent: timeSpentCache[limit.domain] ?? 0,
                        onEdit: { editingLimit = limit },
                        onDelete: { Task { await deleteLimit(limit) } },
                    )
                }
            }
            .listStyle(.inset)
        }
    }

    // MARK: - Actions

    private func refreshLimits() async {
        limits = await browserState.domainTimeTracker.allLimits()

        // Fetch time spent for each limit
        var cache: [String: TimeInterval] = [:]
        for limit in limits {
            cache[limit.domain] = await browserState.domainTimeTracker.timeSpent(on: limit.domain)
        }
        timeSpentCache = cache
    }

    private func deleteLimit(_ limit: DomainTimeLimitData) async {
        await browserState.domainTimeTracker.removeLimit(for: limit.domain)
        await refreshLimits()
    }
}

// MARK: - Time Limit Row

private struct TimeLimitRow: View {
    let limit: DomainTimeLimitData
    let timeSpent: TimeInterval
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var status: LimitStatus {
        let limitSeconds = TimeInterval(limit.effectiveLimitSeconds)
        if timeSpent >= limitSeconds {
            return .exceeded
        } else if timeSpent >= limitSeconds * 0.8 {
            return .warning
        }
        return .ok
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(limit.domain)
                        .font(.body)
                        .fontWeight(.medium)

                    if !limit.isEnabled {
                        Text("Disabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 4))
                    }
                }

                HStack(spacing: 12) {
                    Label(TimeInterval(limit.dailyLimitSeconds).shortDuration, systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label(timeSpent.formattedDuration, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            statusBadge

            Menu {
                Button("Edit…") { onEdit() }
                Divider()
                Button("Delete", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        StatusBadge(status: status)
    }
}

private struct StatusBadge: View {
    let status: LimitStatus

    var body: some View {
        Text(status.label)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }
}

private enum LimitStatus {
    case ok
    case warning
    case exceeded

    var label: String {
        switch self {
        case .ok: "OK"
        case .warning: "Warning"
        case .exceeded: "Exceeded"
        }
    }

    var color: Color {
        switch self {
        case .ok: .green
        case .warning: .orange
        case .exceeded: .red
        }
    }
}

// MARK: - Add Time Limit Sheet

private struct AddTimeLimitSheet: View {
    @Environment(BrowserState.self) private var browserState
    @Environment(\.dismiss) private var dismiss

    let onAdd: () -> Void

    @State private var domain = ""
    @State private var limitMinutes = 30
    @State private var existingDomains: Set<String> = []
    @FocusState private var isFocused: Bool

    private var normalizedDomain: String {
        domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var validationError: String? {
        let input = normalizedDomain
        if input.isEmpty { return nil }

        if existingDomains.contains(input) {
            return "A time limit for this domain already exists"
        }

        if !input.contains(".") {
            return "Enter a valid domain (e.g., twitter.com)"
        }

        return nil
    }

    private var canAdd: Bool {
        !normalizedDomain.isEmpty && validationError == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Add Time Limit")
                    .font(.headline)

                Spacer()

                Button("Add") { addLimit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!canAdd)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Domain")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    TextField("twitter.com", text: $domain)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        .onSubmit {
                            if canAdd { addLimit() }
                        }

                    if let error = validationError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily Limit")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    TimeLimitPicker(minutes: $limitMinutes)
                }

                Spacer()
            }
            .padding(20)
        }
        .frame(width: 350, height: 280)
        .task {
            existingDomains = await Set(browserState.domainTimeTracker.allLimits().map(\.domain))
        }
        .onAppear { isFocused = true }
    }

    private func addLimit() {
        Task {
            await browserState.domainTimeTracker.setLimit(
                for: normalizedDomain,
                limitSeconds: limitMinutes * 60,
                enabled: true,
            )
            dismiss()
            onAdd()
        }
    }
}

// MARK: - Edit Time Limit Sheet

private struct EditTimeLimitSheet: View {
    @Environment(BrowserState.self) private var browserState
    @Environment(\.dismiss) private var dismiss

    let limit: DomainTimeLimitData
    let onSave: () -> Void

    @State private var isEnabled: Bool
    @State private var limitMinutes: Int
    @State private var timeSpent: TimeInterval = 0

    init(limit: DomainTimeLimitData, onSave: @escaping () -> Void) {
        self.limit = limit
        self.onSave = onSave
        _isEnabled = State(initialValue: limit.isEnabled)
        _limitMinutes = State(initialValue: limit.dailyLimitSeconds / 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Edit Time Limit")
                    .font(.headline)

                Spacer()

                Button("Save") { saveLimit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Domain")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(limit.domain)
                        .fontWeight(.medium)
                }

                Toggle("Enabled", isOn: $isEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily Limit")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    TimeLimitPicker(minutes: $limitMinutes)
                }

                HStack {
                    Text("Time spent today")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(timeSpent.formattedDuration)
                }

                Spacer()
            }
            .padding(20)
        }
        .frame(width: 350, height: 300)
        .task {
            timeSpent = await browserState.domainTimeTracker.timeSpent(on: limit.domain)
        }
    }

    private func saveLimit() {
        Task {
            await browserState.domainTimeTracker.setLimit(
                for: limit.domain,
                limitSeconds: limitMinutes * 60,
                enabled: isEnabled,
            )
            dismiss()
            onSave()
        }
    }
}

// MARK: - Shared Components

private struct TimeLimitPicker: View {
    @Binding var minutes: Int

    var body: some View {
        Picker("Limit", selection: $minutes) {
            Text("15 minutes").tag(15)
            Text("30 minutes").tag(30)
            Text("45 minutes").tag(45)
            Text("1 hour").tag(60)
            Text("1.5 hours").tag(90)
            Text("2 hours").tag(120)
            Text("3 hours").tag(180)
            Text("4 hours").tag(240)
        }
        .labelsHidden()
    }
}

// MARK: - Identifiable Conformance

extension DomainTimeLimitData: Identifiable {
    var id: String {
        domain
    }
}
