import SwiftUI
import WebKit

// MARK: - Permission Request Types

/// The type of permission being requested.
enum PermissionRequestType {
    case permissions(Set<WKWebExtension.Permission>)
    case urls(Set<URL>)
    case matchPatterns(Set<WKWebExtension.MatchPattern>)
}

/// Represents a pending permission request that needs user interaction.
struct PermissionRequest: Identifiable {
    let id = UUID()
    let extensionName: String
    let extensionIcon: NSImage?
    let requestType: PermissionRequestType
    let continuation: PermissionContinuation

    /// Response type varies based on request type.
    enum PermissionContinuation {
        case permissions(CheckedContinuation<(Set<WKWebExtension.Permission>, Date?), Never>)
        case urls(CheckedContinuation<(Set<URL>, Date?), Never>)
        case matchPatterns(CheckedContinuation<(Set<WKWebExtension.MatchPattern>, Date?), Never>)
    }
}

// MARK: - Permission Prompt Manager

/// Manages pending permission requests and presents the prompt UI.
@Observable
final class PermissionPromptManager {
    /// The current permission request to show, if any.
    var currentRequest: PermissionRequest?

    /// Queue of pending permission requests.
    private var requestQueue: [PermissionRequest] = []

    /// Enqueues a permission request and shows the prompt if not already showing.
    func enqueue(_ request: PermissionRequest) {
        requestQueue.append(request)
        showNextIfNeeded()
    }

    /// Shows the next request in the queue if nothing is currently showing.
    private func showNextIfNeeded() {
        guard currentRequest == nil, let next = requestQueue.first else { return }
        requestQueue.removeFirst()
        currentRequest = next
    }

    /// Called when the user responds to a permission request.
    func completeCurrentRequest() {
        currentRequest = nil
        showNextIfNeeded()
    }
}

// MARK: - Permission Prompt View

struct ExtensionPermissionPromptView: View {
    let request: PermissionRequest
    let onComplete: () -> Void

    @State private var selectedItems: Set<String> = []
    @State private var permanentGrant = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Permission list
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    permissionsList
                }
                .padding()
            }

            Divider()

            // Footer with options and buttons
            footerSection
        }
        .frame(width: 420, height: 400)
        .onAppear {
            // Select all by default
            selectedItems = allItemIdentifiers
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            extensionIcon
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(request.extensionName)
                    .font(.headline)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var extensionIcon: some View {
        if let icon = request.extensionIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.appAccentColor.opacity(0.15))
                .overlay {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var headerSubtitle: String {
        switch request.requestType {
        case .permissions:
            "wants additional permissions"
        case .urls:
            "wants access to these sites"
        case .matchPatterns:
            "wants access to these URL patterns"
        }
    }

    // MARK: - Permissions List

    @ViewBuilder
    private var permissionsList: some View {
        switch request.requestType {
        case let .permissions(permissions):
            ForEach(Array(permissions), id: \.rawValue) { permission in
                PermissionItemRow(
                    title: permissionDisplayName(permission),
                    description: permissionDescription(permission),
                    identifier: permission.rawValue,
                    isSelected: selectedItems.contains(permission.rawValue),
                    onToggle: { toggleItem(permission.rawValue) },
                )
            }

        case let .urls(urls):
            ForEach(Array(urls), id: \.absoluteString) { url in
                PermissionItemRow(
                    title: url.host ?? url.absoluteString,
                    description: url.absoluteString,
                    identifier: url.absoluteString,
                    isSelected: selectedItems.contains(url.absoluteString),
                    onToggle: { toggleItem(url.absoluteString) },
                )
            }

        case let .matchPatterns(patterns):
            ForEach(Array(patterns), id: \.self) { pattern in
                let patternString = pattern.description
                PermissionItemRow(
                    title: patternDisplayName(pattern),
                    description: patternString,
                    identifier: patternString,
                    isSelected: selectedItems.contains(patternString),
                    onToggle: { toggleItem(patternString) },
                )
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 12) {
            Toggle("Remember this decision", isOn: $permanentGrant)

            HStack {
                Button("Deny All") {
                    denyAll()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Allow Selected") {
                    allowSelected()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedItems.isEmpty)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Actions

    private var allItemIdentifiers: Set<String> {
        switch request.requestType {
        case let .permissions(permissions):
            Set(permissions.map(\.rawValue))
        case let .urls(urls):
            Set(urls.map(\.absoluteString))
        case let .matchPatterns(patterns):
            Set(patterns.map(\.description))
        }
    }

    private func toggleItem(_ identifier: String) {
        if selectedItems.contains(identifier) {
            selectedItems.remove(identifier)
        } else {
            selectedItems.insert(identifier)
        }
    }

    private func denyAll() {
        let expiration: Date? = permanentGrant ? .distantFuture : nil

        switch request.continuation {
        case let .permissions(cont):
            cont.resume(returning: ([], expiration))
        case let .urls(cont):
            cont.resume(returning: ([], expiration))
        case let .matchPatterns(cont):
            cont.resume(returning: ([], expiration))
        }

        onComplete()
    }

    private func allowSelected() {
        let expiration: Date? = permanentGrant ? .distantFuture : nil

        switch request.requestType {
        case let .permissions(permissions):
            let granted = permissions.filter { selectedItems.contains($0.rawValue) }
            if case let .permissions(cont) = request.continuation {
                cont.resume(returning: (granted, expiration))
            }

        case let .urls(urls):
            let granted = urls.filter { selectedItems.contains($0.absoluteString) }
            if case let .urls(cont) = request.continuation {
                cont.resume(returning: (granted, expiration))
            }

        case let .matchPatterns(patterns):
            let granted = patterns.filter { selectedItems.contains($0.description) }
            if case let .matchPatterns(cont) = request.continuation {
                cont.resume(returning: (granted, expiration))
            }
        }

        onComplete()
    }

    // MARK: - Display Names

    private func permissionDisplayName(_ permission: WKWebExtension.Permission) -> String {
        switch permission.rawValue {
        case "activeTab": "Active Tab"
        case "alarms": "Alarms"
        case "clipboardWrite": "Clipboard Write"
        case "contextMenus": "Context Menus"
        case "cookies": "Cookies"
        case "declarativeNetRequest": "Network Request Modification"
        case "declarativeNetRequestFeedback": "Network Request Feedback"
        case "declarativeNetRequestWithHostAccess": "Network Request (Host Access)"
        case "dns": "DNS"
        case "geolocation": "Geolocation"
        case "menus": "Menus"
        case "nativeMessaging": "Native Messaging"
        case "notifications": "Notifications"
        case "scripting": "Scripting"
        case "storage": "Storage"
        case "tabs": "Tabs"
        case "unlimitedStorage": "Unlimited Storage"
        case "webNavigation": "Web Navigation"
        case "webRequest": "Web Request"
        default: permission.rawValue.capitalized
        }
    }

    private func permissionDescription(_ permission: WKWebExtension.Permission) -> String {
        switch permission.rawValue {
        case "activeTab": "Access the currently active tab when you click the extension"
        case "alarms": "Schedule code to run at specific times"
        case "clipboardWrite": "Copy data to your clipboard"
        case "contextMenus": "Add items to the right-click menu"
        case "cookies": "Read and modify cookies"
        case "declarativeNetRequest": "Block or modify network requests"
        case "notifications": "Show desktop notifications"
        case "scripting": "Inject scripts into web pages"
        case "storage": "Store data locally"
        case "tabs": "Access information about browser tabs"
        case "webNavigation": "Monitor navigation events"
        case "webRequest": "Observe and analyze network traffic"
        default: "Access to \(permission.rawValue)"
        }
    }

    private func patternDisplayName(_ pattern: WKWebExtension.MatchPattern) -> String {
        if pattern.matchesAllURLs {
            return "All URLs"
        }
        return pattern.description
    }
}

// MARK: - Permission Item Row

private struct PermissionItemRow: View {
    let title: String
    let description: String
    let identifier: String
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isHovered ? Color.appAccentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
