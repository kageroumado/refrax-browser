import AppKit
import SwiftUI
import UserNotifications

// MARK: - Notifications Settings

/// Websites' notification permissions: whether sites may ask, macOS's permission for Refrax,
/// and every site that asked, with its answer.
struct NotificationsSettingsView: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(BrowserState.self) private var browserState
    @Environment(\.appearsActive) private var appearsActive
    let highlightedItemId: String?

    @State private var selection: Set<String> = []
    @State private var confirmsRemoveAll = false

    private var manager: WebNotificationManager {
        browserState.webNotifications
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Allow websites to ask for permission to send notifications", isOn: $settings.allowWebsiteNotificationRequests)
                    .highlightable(id: "notifications.allowRequests", highlightedItemId: highlightedItemId)
            } footer: {
                Text("When off, websites can't ask. Websites you already allowed can still send notifications.")
            }

            systemSection
            websitesSection
        }
        .formStyle(.grouped)
        // Coming back from System Settings makes the window active again.
        .task(id: appearsActive) {
            if appearsActive {
                await manager.refreshSystemAuthorization()
            }
        }
        .confirmationDialog("Remove all websites?", isPresented: $confirmsRemoveAll) {
            Button("Remove All", role: .destructive) {
                manager.removeAll()
                selection.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each website asks again the next time it wants to send notifications.")
        }
    }

    // MARK: macOS

    private var systemSection: some View {
        Section {
            LabeledContent("Notifications from Refrax") {
                HStack(spacing: 8) {
                    Text(systemStatus)
                        .foregroundStyle(.secondary)
                    if manager.systemAuthorization == .denied {
                        Button("Open System Settings…") {
                            manager.openSystemNotificationSettings()
                        }
                    }
                }
            }
            .highlightable(id: "notifications.system", highlightedItemId: highlightedItemId)
        } header: {
            Text("macOS")
        } footer: {
            Text(systemFooter)
        }
    }

    private var systemStatus: String {
        switch manager.systemAuthorization {
        case .authorized, .provisional, .ephemeral: "On"
        case .denied: "Off"
        default: "Not set up"
        }
    }

    private var systemFooter: String {
        switch manager.systemAuthorization {
        case .denied:
            "macOS is blocking Refrax's notifications, so websites' notifications don't appear. Turn them on in System Settings."
        case .authorized, .provisional, .ephemeral:
            "Banner style, sounds, and Focus are set for Refrax in System Settings."
        default:
            "Refrax asks macOS the first time you allow a website."
        }
    }

    // MARK: Websites

    private var websitesSection: some View {
        Section {
            if manager.permissions.isEmpty {
                ContentUnavailableView {
                    Label("No Websites", systemImage: "bell.slash")
                } description: {
                    Text("Websites that ask to send you notifications appear here.")
                }
            } else {
                websiteList
                HStack {
                    Button("Remove") { remove(selection) }
                        .disabled(selection.isEmpty)
                    Spacer()
                    Button("Remove All…") { confirmsRemoveAll = true }
                }
            }
        } header: {
            Text("Websites")
        } footer: {
            Text("A removed website asks again the next time it wants to send notifications. Private spaces never allow notifications.")
        }
        .highlightable(id: "notifications.sites", highlightedItemId: highlightedItemId)
    }

    private var websiteList: some View {
        List(selection: $selection) {
            ForEach(manager.permissions, id: \.origin) { permission in
                NotificationPermissionRow(
                    permission: permission,
                    faviconCache: browserState.faviconCache,
                    setState: { state in
                        if let origin = permission.webOrigin {
                            manager.setState(state, for: origin)
                        }
                    },
                )
                .tag(permission.origin)
            }
        }
        .listStyle(.bordered)
        .alternatingRowBackgrounds()
        .frame(minHeight: Layout.listMinHeight)
        .contextMenu(forSelectionType: String.self) { origins in
            Button("Remove", role: .destructive) { remove(origins) }
                .disabled(origins.isEmpty)
        }
        .onDeleteCommand { remove(selection) }
    }

    private func remove(_ origins: Set<String>) {
        manager.remove(origins.compactMap(WebOrigin.init(string:)))
        selection.subtract(origins)
    }

    private enum Layout {
        static let listMinHeight: CGFloat = 220
    }
}

// MARK: - Website Row

/// One website that asked: its icon and host, how much it has notified, and its answer.
private struct NotificationPermissionRow: View {
    let permission: WebNotificationPermission
    let faviconCache: FaviconCache
    let setState: (WebNotificationPermission.State) -> Void

    @State private var faviconData: Data?

    private var origin: WebOrigin? {
        permission.webOrigin
    }

    var body: some View {
        HStack(spacing: 10) {
            FaviconView(data: faviconData, url: origin?.url, size: Layout.faviconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(origin?.displayName ?? permission.origin)
                    .lineLimit(1)
                    .truncationMode(.middle)
                activity
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Notifications from \(origin?.displayName ?? permission.origin)", selection: Binding(
                get: { permission.state },
                set: { setState($0) },
            )) {
                Text("Allow").tag(WebNotificationPermission.State.granted)
                Text("Deny").tag(WebNotificationPermission.State.denied)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.vertical, 2)
        .task(id: permission.origin) {
            guard let host = origin?.host, !host.isEmpty else { return }
            faviconData = await faviconCache.cachedFaviconData(forHost: host, size: .small)
        }
    }

    @ViewBuilder
    private var activity: some View {
        if let last = permission.lastNotificationAt {
            let count = permission.notificationCount
            Text("\(count) notification\(count == 1 ? "" : "s"), last \(last, format: .relative(presentation: .named))")
        } else {
            Text("No notifications yet")
        }
    }

    private enum Layout {
        static let faviconSize: CGFloat = 20
    }
}
