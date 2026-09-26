import AppKit
import Foundation
import Observation
import SwiftData
import UserNotifications
import WebKit

/// Web notifications for every engine: asking, remembering, delivering, and clicking.
///
/// ## Permissions
/// One decision per origin (``WebNotificationPermission``), shared by all non-private
/// spaces. WebKit's live-update SPI reaches every running web process of a process pool at
/// once, so a per-space answer could not be kept consistent in pages that are already open.
/// Private spaces never ask and never store: their data stores are ephemeral, where WebKit
/// denies notifications itself.
///
/// WebKit learns the decisions through the data store delegate and the notification
/// providers when a web process launches, and through ``RFXWebNotificationProvider`` pushes
/// when the user changes one, so `Notification.permission` is right in open pages too.
///
/// ## Delivery
/// Page notifications arrive through a provider on each process pool's manager, service
/// worker notifications through the provider on WebKit's shared service worker manager, and
/// engine notifications through page events. All become `UNNotificationRequest`s; a click
/// fires the page's `click` or the worker's `notificationclick` and brings the tab forward.
///
/// Web Push (delivery while no page or worker runs) needs Apple's `webpushd`, which only
/// Safari can use; the Push API stays off (`PushAPIEnabled` defaults off for embedders), so
/// `registration.pushManager` is undefined.
@Observable
final class WebNotificationManager {
    // MARK: Constants

    nonisolated enum Constants {
        /// Largest service worker notification description kept for a click after relaunch.
        static let maximumPersistentRepresentationBytes = 16 * 1024
        /// Largest notification icon Refrax downloads.
        static let maximumIconBytes = 1_000_000
        /// How long an icon download may take before the notification goes without it.
        static let iconTimeout: TimeInterval = 3
    }

    // MARK: Observed State

    /// Every origin that asked, ordered by host.
    private(set) var permissions: [WebNotificationPermission] = []

    /// Whether macOS lets Refrax show notifications.
    private(set) var systemAuthorization: UNAuthorizationStatus = .notDetermined

    // MARK: Dependencies

    @ObservationIgnored let store: WebNotificationPermissionStore
    @ObservationIgnored let settings: BrowserSettings

    /// Tabs, windows, and data stores for routing clicks. Set after the pool is created.
    @ObservationIgnored weak var pagePool: WebPagePool?

    /// Receives ``enginePolicy`` whenever a decision or the ask setting changes, so engines
    /// answer permission from Refrax's store alone.
    @ObservationIgnored var onEnginePolicyChange: ((NotificationPolicy) -> Void)? {
        didSet { publishEnginePolicy() }
    }

    // MARK: WebKit Plumbing

    /// Page notification providers, one per process pool, keyed by manager.
    @ObservationIgnored var providers: [UInt: RFXWebNotificationProvider] = [:]
    @ObservationIgnored var serviceWorkerProvider: RFXWebNotificationProvider?
    @ObservationIgnored let providerDelegate = WebNotificationProviderDelegate()
    @ObservationIgnored let dataStoreDelegate = WebNotificationDataStoreDelegate()
    @ObservationIgnored private var askSettingObservation: Task<Void, Never>?

    // MARK: Deliveries

    /// Where each delivered request came from, by request identifier.
    @ObservationIgnored var sourcesByRequest: [String: IncomingWebNotification.Source] = [:]
    @ObservationIgnored var requestsBySource: [IncomingWebNotification.Source: String] = [:]

    // MARK: Initialization

    init(modelContext: ModelContext, settings: BrowserSettings) {
        self.store = WebNotificationPermissionStore(modelContext: modelContext)
        self.settings = settings
        self.permissions = store.records
        providerDelegate.manager = self
        dataStoreDelegate.manager = self
        observeAskSetting()
    }

    isolated deinit {
        askSettingObservation?.cancel()
    }

    // MARK: - Asking

    /// Answers a page's request to show notifications: the stored decision, or the user's
    /// answer to the page's prompt, which is then stored.
    ///
    /// - Parameters:
    ///   - origin: The origin asking.
    ///   - isPrivate: Whether the page belongs to a private space; those are denied unasked and nothing is stored.
    ///   - prompts: The page's question queue.
    /// - Returns: Whether the origin may show notifications.
    func requestPermission(for origin: WebOrigin, isPrivate: Bool, prompts: PagePrompts) async -> Bool {
        guard !isPrivate else { return false }
        switch store.state(for: origin) {
        case .granted?:
            return true
        case .denied?:
            return false
        case nil:
            break
        }
        guard settings.allowWebsiteNotificationRequests else { return false }

        switch await prompts.ask(.permission(kind: .notifications, origin: origin.siteName)) {
        case .accept, .acceptAndRemember, .text:
            setState(.granted, for: origin)
            Task(name: "macOS notification authorization") {
                await requestSystemAuthorizationIfNeeded()
            }
            return true
        case .declineAndRemember:
            setState(.denied, for: origin)
            return false
        case .decline:
            return false
        }
    }

    /// The origin's state as the Permissions API reports it.
    func permissionDecision(for origin: WebOrigin, isPrivate: Bool) -> WKPermissionDecision {
        guard !isPrivate else { return .prompt }
        switch store.state(for: origin) {
        case .granted?: return .grant
        case .denied?: return .deny
        case nil: return settings.allowWebsiteNotificationRequests ? .prompt : .deny
        }
    }

    // MARK: - Changing Permissions

    /// Sets an origin's decision and tells running pages.
    func setState(_ state: WebNotificationPermission.State, for origin: WebOrigin) {
        guard store.state(for: origin) != state else { return }
        store.setState(state, for: origin)
        permissions = store.records
        forEachProvider { $0.updatePermission(state == .granted, for: origin.string) }
        publishEnginePolicy()
        Logger.info("Notifications \(state.rawValue) for \(origin)", category: Logger.notifications)
    }

    /// Forgets the origins, so each asks again, and tells running pages.
    func remove(_ origins: [WebOrigin]) {
        let origins = origins.filter { store.state(for: $0) != nil }
        guard !origins.isEmpty else { return }
        store.remove(origins)
        permissions = store.records
        let strings = origins.map(\.string)
        forEachProvider { $0.removePermissions(for: strings) }
        publishEnginePolicy()
    }

    /// Forgets every origin.
    func removeAll() {
        remove(permissions.compactMap(\.webOrigin))
    }

    /// Origin string → granted, as WebKit takes permissions.
    var permissionMap: [String: NSNumber] {
        store.permissionMap.mapValues { NSNumber(value: $0) }
    }

    /// Every decision, in the form engines take it.
    var enginePolicy: NotificationPolicy {
        var policy = NotificationPolicy(asksByDefault: settings.allowWebsiteNotificationRequests)
        for (origin, granted) in store.permissionMap.sorted(by: { $0.key < $1.key }) {
            if granted {
                policy.granted.append(origin)
            } else {
                policy.denied.append(origin)
            }
        }
        return policy
    }

    private func publishEnginePolicy() {
        onEnginePolicyChange?(enginePolicy)
    }

    /// Republishes the engine policy when the ask setting changes.
    ///
    /// The settings model is read only while it still has a context: the observation can
    /// re-evaluate after its store is torn down, and reading a detached model traps.
    private func observeAskSetting() {
        let changes = Observations { [weak settings] () -> Bool? in
            guard let settings, settings.modelContext != nil else { return nil }
            return settings.allowWebsiteNotificationRequests
        }
        askSettingObservation = Task(name: "Notification ask setting") { [weak self] in
            for await value in changes {
                guard let self, value != nil else { break }
                publishEnginePolicy()
            }
        }
    }

    private func forEachProvider(_ body: (RFXWebNotificationProvider) -> Void) {
        for provider in providers.values {
            body(provider)
        }
        if let serviceWorkerProvider {
            body(serviceWorkerProvider)
        }
    }

    // MARK: - macOS Authorization

    /// Reads whether macOS lets Refrax show notifications.
    func refreshSystemAuthorization() async {
        systemAuthorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks macOS for permission the first time a site is allowed.
    func requestSystemAuthorizationIfNeeded() async {
        await refreshSystemAuthorization()
        guard systemAuthorization == .notDetermined else { return }
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Logger.warning("macOS notification authorization failed: \(error)", category: Logger.notifications)
        }
        await refreshSystemAuthorization()
    }

    /// Whether macOS currently delivers Refrax's notifications.
    var systemAllowsNotifications: Bool {
        switch systemAuthorization {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    /// Opens Refrax's page in System Settings > Notifications.
    func openSystemNotificationSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)")
            ?? URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.open(url)
    }
}
