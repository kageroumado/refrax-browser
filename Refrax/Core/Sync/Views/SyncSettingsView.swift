import SwiftUI

// MARK: - Sync Settings

struct SyncSettingsView: View {
    let highlightedItemId: String?

    @Environment(BrowserSettings.self) private var settings

    @State private var showResetAlert = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            syncToggleSection(iCloudSyncEnabled: $settings.iCloudSyncEnabled)
            statusSection
            accountSection
            resetSection
        }
        .formStyle(.grouped)
        .alert("Reset Sync Data", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetSyncData()
            }
        } message: {
            Text("This removes all sync metadata and re-uploads your local data on the next sync. Your local data is not affected.")
        }
    }

    // MARK: - Sections

    private func syncToggleSection(iCloudSyncEnabled: Binding<Bool>) -> some View {
        Section {
            Toggle("Sync with iCloud", isOn: iCloudSyncEnabled)
                .highlightable(id: "sync.enabled", highlightedItemId: highlightedItemId)
        } header: {
            Text("iCloud Sync")
        } footer: {
            Text("Keep tabs, bookmarks, history, and settings in sync across all your Macs signed into the same iCloud account.")
        }
    }

    private var statusSection: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                Group {
                    if settings.iCloudSyncEnabled {
                        Label("Up to date", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Disabled")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }
            .highlightable(id: "sync.status", highlightedItemId: highlightedItemId)
        } header: {
            Text("Status")
        }
    }

    private var accountSection: some View {
        Section {
            HStack {
                Text("iCloud Account")
                Spacer()
                Text("Signed In")
                    .foregroundStyle(.secondary)
            }
            .highlightable(id: "sync.account", highlightedItemId: highlightedItemId)
        } header: {
            Text("Account")
        } footer: {
            Text("Sync uses your iCloud private database. Data is end-to-end encrypted and never shared.")
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showResetAlert = true
            } label: {
                Text("Reset Sync Data")
            }
            .highlightable(id: "sync.reset", highlightedItemId: highlightedItemId)
        } header: {
            Text("Advanced")
        } footer: {
            Text("If sync gets stuck or shows incorrect data, resetting will clear all sync metadata and re-upload from this Mac.")
        }
    }

    // MARK: - Actions

    private func resetSyncData() {
        // Will be wired to SyncCoordinator in a follow-up task
    }
}
