import SwiftUI

// MARK: - Feature Flags Settings

struct FeatureFlagsSettingsView: View {
    @Environment(BrowserSettings.self) private var settings
    let highlightedItemId: String?

    @State private var showResetAlert = false

    var body: some View {
        Form {
            ForEach(FeatureFlagDefinition.Category.allCases, id: \.self) { category in
                let flags = FeatureFlagDefinition.definitions(for: category)
                if !flags.isEmpty {
                    Section(category.rawValue) {
                        ForEach(flags) { flag in
                            FeatureFlagRow(flag: flag)
                                .highlightable(
                                    id: "featureFlags.\(flag.key)",
                                    highlightedItemId: highlightedItemId
                                )
                        }
                    }
                }
            }

            Section {
                Button("Reset All Feature Flags") {
                    showResetAlert = true
                }
                .disabled(!settings.hasFeatureFlagOverrides)
            } footer: {
                Text("Changes apply to new tabs. Reload existing tabs for changes to take effect.")
            }
        }
        .formStyle(.grouped)
        .alert("Reset Feature Flags", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                settings.resetFeatureFlags()
            }
        } message: {
            Text("This will reset all feature flags to their default values.")
        }
    }
}

// MARK: - Feature Flag Row

private struct FeatureFlagRow: View {
    let flag: FeatureFlagDefinition
    @Environment(BrowserSettings.self) private var settings

    private var isEnabled: Bool {
        settings.isFeatureFlagEnabled(flag.key, default: flag.defaultValue)
    }

    private var isOverridden: Bool {
        settings.featureFlagOverrides[flag.key] != nil
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { isEnabled },
            set: { settings.setFeatureFlag(flag.key, enabled: $0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(flag.name)

                    if isOverridden {
                        Text("Modified")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.appAccentColor),
                            )
                    }
                }

                Text(flag.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .contextMenu {
            if isOverridden {
                Button("Reset to Default") {
                    settings.setFeatureFlag(flag.key, enabled: nil)
                }
            }
        }
    }
}
