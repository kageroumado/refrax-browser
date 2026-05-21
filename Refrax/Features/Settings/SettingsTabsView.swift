import SwiftData
import SwiftUI

// MARK: - Tabs Settings

struct TabsSettingsView: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(ScheduledTasksManager.self) private var scheduledTasksManager
    @Environment(TabArchiveManager.self) private var archiveManager
    @Environment(\.modelContext) private var modelContext

    let highlightedItemId: String?

    @State private var showAutoArchiveRulesSheet = false
    @State private var showDisableArchiveAlert = false
    @State private var showTimeLimitsSheet = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            // MARK: - Previews

            Section {
                Toggle("Show tab previews on hover", isOn: $settings.showTabPreviews)
                    .highlightable(id: "tabs.showPreviews", highlightedItemId: highlightedItemId)
            } header: {
                Text("Previews")
            } footer: {
                Text("Display a thumbnail preview when hovering over tabs in the sidebar.")
            }

            // MARK: - Archive

            Section {
                Toggle("Enable tab archive", isOn: Binding(
                    get: { settings.archiveEnabled },
                    set: { newValue in
                        if !newValue {
                            showDisableArchiveAlert = true
                        } else {
                            settings.archiveEnabled = true
                        }
                    },
                ))
                .highlightable(id: "tabs.archiveEnabled", highlightedItemId: highlightedItemId)

                if settings.archiveEnabled {
                    Picker("Clear archived tabs after", selection: $settings.archiveClearHours) {
                        Text("1 hour").tag(1 as Int?)
                        Text("6 hours").tag(6 as Int?)
                        Text("24 hours").tag(24 as Int?)
                        Text("1 week").tag(168 as Int?)
                        Text("Never").tag(nil as Int?)
                    }
                    .highlightable(id: "tabs.archiveExpiration", highlightedItemId: highlightedItemId)
                }
            } header: {
                Text("Archive")
            } footer: {
                Text("Closed tabs move to an Archive group instead of being deleted, allowing recovery.")
            }

            // MARK: - Auto-Archive/Close Rules

            Section {
                Toggle(autoRulesToggleLabel, isOn: $settings.autoArchiveRulesEnabled)
                    .highlightable(id: "tabs.autoArchiveRules", highlightedItemId: highlightedItemId)

                if settings.autoArchiveRulesEnabled {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Manage rules")
                            lastCheckText
                        }
                        Spacer()
                        Button("Edit…") {
                            showAutoArchiveRulesSheet = true
                        }
                    }
                    .highlightable(id: "tabs.manageRules", highlightedItemId: highlightedItemId)
                }
            } header: {
                Text(autoRulesSectionHeader)
            } footer: {
                Text(autoRulesFooter)
            }

            // MARK: - Snapshots

            Section {
                Toggle("Enable automatic snapshots", isOn: $settings.enableAutomaticSnapshots)
                    .highlightable(id: "tabs.snapshots", highlightedItemId: highlightedItemId)

                if settings.enableAutomaticSnapshots {
                    Picker("Keep snapshots for", selection: $settings.snapshotRetentionDays) {
                        Text("1 week").tag(7)
                        Text("2 weeks").tag(14)
                        Text("1 month").tag(30)
                        Text("3 months").tag(90)
                    }
                    .highlightable(id: "tabs.snapshotRetention", highlightedItemId: highlightedItemId)

                    Picker("Maximum snapshots", selection: $settings.maxSnapshotCount) {
                        Text("50").tag(50)
                        Text("100").tag(100)
                        Text("200").tag(200)
                        Text("300").tag(300)
                        Text("500").tag(500)
                    }
                    .highlightable(id: "tabs.maxSnapshots", highlightedItemId: highlightedItemId)
                }
            } header: {
                Text("Snapshots")
            } footer: {
                Text("Snapshots save tab state periodically for recovery. Older snapshots are automatically cleaned up.")
            }

            // MARK: - Video Fullscreen

            Section {
                Toggle("In-window video fullscreen", isOn: Binding(
                    get: { settings.inWindowFullscreenEnabled ?? false },
                    set: { settings.inWindowFullscreenEnabled = $0 }
                ))
                .highlightable(id: "tabs.inWindowFullscreen", highlightedItemId: highlightedItemId)
            } header: {
                Text("Video")
            } footer: {
                Text("Videos enter fullscreen within the browser window instead of taking over the entire screen. Requires creating a new tab to take effect.")
            }

            // MARK: - Notifications

            Section {
                Toggle("Detect notification badges in page titles", isOn: $settings.badgeDetectionEnabled)
                    .highlightable(id: "tabs.badgeDetection", highlightedItemId: highlightedItemId)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Mark tabs as unread when their titles contain notification counts like \"(3) Gmail\".")
            }

            // MARK: - Indicators

            Section {
                Toggle("Show indicator for tabs with unsaved form data", isOn: $settings.showUnsavedFormIndicator)
                    .highlightable(id: "tabs.showUnsavedFormIndicator", highlightedItemId: highlightedItemId)
            } header: {
                Text("Indicators")
            } footer: {
                Text("Display a pencil icon next to tabs that have form fields with unsaved user input.")
            }

            // MARK: - Time Tracking

            Section {
                Toggle("Show time spent in tab tooltips", isOn: $settings.showTimeSpentInTooltips)
                    .highlightable(id: "tabs.showTimeInTooltips", highlightedItemId: highlightedItemId)

                HStack {
                    Text("Daily time limits")
                    Spacer()
                    Button("Manage...") {
                        showTimeLimitsSheet = true
                    }
                }
                .highlightable(id: "tabs.timeLimits", highlightedItemId: highlightedItemId)
            } header: {
                Text("Time Tracking")
            } footer: {
                Text("Track time spent on websites. Set daily limits to help manage browsing time on specific sites.")
            }
        }
        .formStyle(.grouped)
        .alert("Disable Tab Archive?", isPresented: $showDisableArchiveAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disable", role: .destructive) {
                settings.archiveEnabled = false
                archiveManager.clearAllArchives(context: modelContext)
            }
        } message: {
            Text("Disabling the archive will permanently delete all archived tabs in every space. This cannot be undone.")
        }
        .sheet(isPresented: $showAutoArchiveRulesSheet) {
            AutoArchiveRulesSheet()
        }
        .sheet(isPresented: $showTimeLimitsSheet) {
            TimeLimitsSettingsView()
        }
    }

    private var lastCheckText: some View {
        Group {
            if let lastRun = scheduledTasksManager.lastTaskRun {
                Text("Last check: \(lastRun.relativeFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not yet checked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Dynamic Auto-Rules Labels

    private var autoRulesSectionHeader: String {
        settings.archiveEnabled ? "Auto-Archive Rules" : "Auto-Close Rules"
    }

    private var autoRulesToggleLabel: String {
        settings.archiveEnabled ? "Enable automatic archiving rules" : "Enable automatic close rules"
    }

    private var autoRulesFooter: String {
        if settings.archiveEnabled {
            "Rules run hourly to automatically archive tabs based on inactivity or tab count limits. Pinned tabs, tabs with active media, and tabs with unsaved forms are protected."
        } else {
            "Rules run hourly to automatically close tabs based on inactivity or tab count limits. Pinned tabs, tabs with active media, and tabs with unsaved forms are protected."
        }
    }
}
