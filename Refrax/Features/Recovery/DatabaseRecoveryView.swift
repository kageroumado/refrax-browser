import SwiftUI

/// Recovery dialog presented when the database fails to load during startup.
///
/// Shows a categorized list of model tables, separating incompatible models
/// (which must be reset) from healthy ones (which can optionally be reset).
/// Creates a backup before any destructive operations.
///
/// This view is displayed as a standalone window since the app hasn't fully
/// launched when database recovery is needed.
struct DatabaseRecoveryView: View {
    let diagnosis: DatabaseRecoveryService.DiagnosisResult
    let onRecover: ([String]) -> Void
    let onResetAll: () -> Void
    let onQuit: () -> Void

    @State private var additionalResets: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            scrollableContent
            Divider()
            footer
        }
        .frame(width: 520, height: 400)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Database Recovery", systemImage: "wrench.and.screwdriver")
                .font(.title2.weight(.semibold))

            Text(
                "Refrax's database needs repair. Some data types are "
                    + "incompatible with this version.",
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    // MARK: - Content

    private var scrollableContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !diagnosis.incompatibleModels.isEmpty {
                    incompatibleSection
                }
                if !diagnosis.healthyModels.isEmpty {
                    healthySection
                }
            }
            .padding(20)
        }
    }

    private var incompatibleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Will be reset (incompatible)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            ForEach(diagnosis.incompatibleModels, id: \.name) { model in
                incompatibleRow(model)
            }
        }
    }

    private var healthySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Will be preserved (compatible)", systemImage: "checkmark.shield.fill")
                .foregroundStyle(.green)

            ForEach(diagnosis.healthyModels, id: \.name) { model in
                healthyRow(model)
            }
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
    }

    private func incompatibleRow(_ model: DatabaseRecoveryService.ModelStatus) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.square.fill")
                .foregroundStyle(.tertiary)

            Text(model.displayName)
                .font(.body)

            Text("--")
                .foregroundStyle(.tertiary)

            Text(statusDescription(for: model))
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.leading, 4)
    }

    private func healthyRow(_ model: DatabaseRecoveryService.ModelStatus) -> some View {
        HStack(spacing: 8) {
            let isSelected = additionalResets.contains(model.name)

            Button {
                if isSelected {
                    additionalResets.remove(model.name)
                } else {
                    additionalResets.insert(model.name)
                }
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            Text(model.displayName)
                .font(.body)

            Text("--")
                .foregroundStyle(.tertiary)

            Text(statusDescription(for: model))
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.leading, 4)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "A backup will be created before any changes.",
                systemImage: "externaldrive.badge.checkmark",
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Button("Recover Selected", action: recoverSelected)
                    .keyboardShortcut(.defaultAction)

                Spacer()

                Button("Reset All", role: .destructive, action: onResetAll)

                Button("Quit") {
                    onQuit()
                }
            }
        }
        .padding(20)
    }

    // MARK: - Actions

    private func recoverSelected() {
        var tableNames = diagnosis.incompatibleModels.map(\.name)
        tableNames.append(contentsOf: additionalResets)
        onRecover(tableNames)
    }

    // MARK: - Helpers

    private func statusDescription(for model: DatabaseRecoveryService.ModelStatus) -> String {
        if !model.reason.isEmpty {
            return model.reason
        }
        return formatCount(model.rowCount)
    }

    private func formatCount(_ count: Int) -> String {
        let formatted = count.formatted()
        return count == 1 ? "\(formatted) entry" : "\(formatted) entries"
    }
}
