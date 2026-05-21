import SwiftUI

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(CalendarManager.self) private var calendarManager
    let highlightedItemId: String?

    @State private var showImportSheet = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            // MARK: - Getting Started

            Section {
                Toggle("Show sidebar guide on empty tab", isOn: $settings.showSidebarHints)
                    .highlightable(id: "general.sidebarHints", highlightedItemId: highlightedItemId)

                HStack {
                    VStack(alignment: .leading) {
                        Text("Import from Another Browser")
                        Text("Bookmarks, history, and passwords")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Import…") {
                        showImportSheet = true
                    }
                }
                .highlightable(id: "general.importBrowserData", highlightedItemId: highlightedItemId)
            } header: {
                Text("Getting Started")
            } footer: {
                Text("Displays a quick reference guide in the main area when no tab is open.")
            }

            // MARK: - Gestures

            Section {
                Toggle("Two-finger swipe to switch spaces", isOn: $settings.spaceSwipeGestureEnabled)
                    .highlightable(id: "general.spaceSwipeGesture", highlightedItemId: highlightedItemId)
            } header: {
                Text("Gestures")
            } footer: {
                Text("Swipe left or right on the sidebar to change spaces.")
            }

            // MARK: - Link Previews

            Section {
                Toggle("Shift+Click to preview links", isOn: $settings.shiftClickLinkPreviewEnabled)
                    .highlightable(id: "general.shiftClickLinkPreview", highlightedItemId: highlightedItemId)

                Toggle("Show modifier key hints", isOn: $settings.showModifierKeyHints)
                    .highlightable(id: "general.modifierKeyHints", highlightedItemId: highlightedItemId)
            } header: {
                Text("Link Previews")
            } footer: {
                Text("Hold Shift and click a link to show a Quick Look preview instead of navigating.")
            }

            // MARK: - Media

            Section {
                Toggle("Auto Picture-in-Picture when switching tabs", isOn: $settings.autoPiPOnTabSwitch)
                    .highlightable(id: "general.autoPiP", highlightedItemId: highlightedItemId)
            } header: {
                Text("Media")
            } footer: {
                Text("Automatically enter Picture-in-Picture when leaving a tab with a playing video.")
            }

            // MARK: - Mail

            Section {
                mailHandlerPicker
                    .highlightable(id: "general.mailHandler", highlightedItemId: highlightedItemId)
            } header: {
                Text("Email Links")
            } footer: {
                Text(settings.preferredMailHandler.displayDescription)
            }

            // MARK: - Clipboard

            Section {
                Toggle("Monitor clipboard for URLs", isOn: $settings.clipboardLinkMonitoring)
                    .highlightable(id: "general.clipboardMonitoring", highlightedItemId: highlightedItemId)
            } header: {
                Text("Clipboard")
            } footer: {
                Text("Show a toast to quickly open URLs copied from other apps.")
            }

            // MARK: - Downloads

            Section {
                HStack {
                    Text("Save downloaded files to")
                    Spacer()
                    Text(downloadDirectoryDisplayPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") {
                        chooseDownloadDirectory()
                    }
                }
                .highlightable(id: "general.downloadDirectory", highlightedItemId: highlightedItemId)

                if settings.customDownloadDirectory != nil {
                    Button("Reset to Default") {
                        settings.customDownloadDirectory = nil
                        downloadManager.downloadDirectory = FileManager.default.urls(
                            for: .downloadsDirectory,
                            in: .userDomainMask,
                        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
                    }
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Downloads")
            } footer: {
                Text("Default location for downloaded files. Individual spaces can override this in their settings.")
            }

            // MARK: - Advanced Downloads (aria2)

            Section {
                Toggle("Use aria2 for large files", isOn: $settings.useAria2ForLargeFiles)
                    .highlightable(id: "general.useAria2", highlightedItemId: highlightedItemId)

                if settings.useAria2ForLargeFiles {
                    Picker("Size threshold", selection: $settings.aria2ThresholdMB) {
                        Text("10 MB").tag(10)
                        Text("25 MB").tag(25)
                        Text("50 MB").tag(50)
                        Text("100 MB").tag(100)
                        Text("250 MB").tag(250)
                    }
                    .highlightable(id: "general.aria2Threshold", highlightedItemId: highlightedItemId)

                    Toggle("Enable BitTorrent", isOn: $settings.enableBitTorrent)
                        .highlightable(id: "general.enableBitTorrent", highlightedItemId: highlightedItemId)
                }
            } header: {
                Text("Advanced Downloads")
            } footer: {
                if settings.useAria2ForLargeFiles {
                    if settings.enableBitTorrent {
                        Text("aria2 uses multiple connections for faster downloads. BitTorrent support enables magnet links and .torrent files. Downloads are not seeded by default.")
                    } else {
                        Text("aria2 uses multiple connections for faster downloads. Files larger than the threshold will download faster on good connections.")
                    }
                } else {
                    Text("aria2 is a download accelerator that uses multiple connections per file for faster downloads on large files.")
                }
            }

            // MARK: - Video Downloads (yt-dlp)

            YTDLPSettingsSection(settings: settings, highlightedItemId: highlightedItemId)

            // MARK: - Calendar Widget

            Section {
                Toggle("Show calendar widget in sidebar", isOn: $settings.showCalendarWidget)
                    .highlightable(id: "general.showCalendarWidget", highlightedItemId: highlightedItemId)
                    .onChange(of: settings.showCalendarWidget) { _, enabled in
                        if enabled, calendarManager.authorizationStatus == .notDetermined {
                            Task {
                                await calendarManager.requestAccess()
                            }
                        }
                    }

                if settings.showCalendarWidget {
                    Picker("Show events in next", selection: $settings.calendarLookAheadHours) {
                        Text("6 hours").tag(6)
                        Text("12 hours").tag(12)
                        Text("24 hours").tag(24)
                        Text("48 hours").tag(48)
                        Text("1 week").tag(168)
                    }
                    .highlightable(id: "general.calendarLookAhead", highlightedItemId: highlightedItemId)

                    Toggle("Auto-expand for imminent events", isOn: $settings.calendarAutoExpandOnImminent)
                        .highlightable(id: "general.calendarAutoExpand", highlightedItemId: highlightedItemId)
                }
            } header: {
                Text("Calendar Widget")
            } footer: {
                Text("Display upcoming events from your calendars in the sidebar. Configure calendars in System Settings > Calendar.")
            }

            // External URL handling section
            ExternalURLSettingsView(highlightedItemId: highlightedItemId)
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showImportSheet) {
            ImportWizardView()
        }
    }

    // MARK: - Mail Handler Picker

    @ViewBuilder
    private var mailHandlerPicker: some View {
        @Bindable var settings = settings

        Picker(selection: $settings.preferredMailHandler) {
            ForEach(MailHandler.allCases, id: \.self) { handler in
                Label {
                    Text(handler == .system ? systemMailHandlerLabel : handler.displayName)
                } icon: {
                    if handler == .system, let icon = MailHandler.defaultMailAppIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: handler.iconName)
                    }
                }
                .tag(handler)
            }
        } label: {
            Text("Open email links with")
        }
    }

    private var systemMailHandlerLabel: String {
        let appName = MailHandler.defaultMailAppName
        return appName == "Mail" ? "Mail (System Default)" : "\(appName) (System Default)"
    }

    // MARK: - Download Directory

    private var downloadDirectoryDisplayPath: String {
        let path = downloadManager.downloadDirectory.path
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homeDir) {
            return "~" + path.dropFirst(homeDir.count)
        }
        return path
    }

    private func chooseDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = downloadManager.downloadDirectory
        panel.prompt = "Choose"
        panel.message = "Select a folder for downloaded files"

        if panel.runModal() == .OK, let url = panel.url {
            settings.customDownloadDirectory = url.path
            downloadManager.downloadDirectory = url
        }
    }
}
