import AppKit
import Foundation
import SwiftData

/// Handles URLs opened from external applications.
///
/// When another app opens a URL in Refrax, this handler determines how
/// to process it based on user settings and rules.
///
/// ## Integration
///
/// This handler is invoked from `WindowManager.openExternalURL(_:)`.
/// The typical flow is:
///
/// ```
/// AppDelegate receives URL event
///     ↓
/// WindowManager.openExternalURL
///     ↓
/// ExternalURLHandler.openExternal(_:from:)
///     ↓
/// Execute resolved action
/// ```
///
/// ## Source App Detection
///
/// The handler can optionally receive the bundle ID of the app that
/// opened the URL, enabling per-app rules. This is detected via
/// `NSWorkspace.shared.frontmostApplication` before Refrax activates.
final class ExternalURLHandler {
    // MARK: - Dependencies

    private unowned let tabManager: TabManager
    private unowned let windowManager: WindowManager
    private let settings: BrowserSettings

    // MARK: - Initialization

    /// Creates an external URL handler.
    ///
    /// - Parameters:
    ///   - tabManager: For creating tabs.
    ///   - windowManager: For creating windows and Glimpse windows.
    ///   - settings: Browser settings containing external URL configuration.
    init(
        tabManager: TabManager,
        windowManager: WindowManager,
        settings: BrowserSettings,
    ) {
        self.tabManager = tabManager
        self.windowManager = windowManager
        self.settings = settings
    }

    // MARK: - Handling

    /// Opens a URL received from an external application.
    ///
    /// - Parameters:
    ///   - url: The URL to open.
    ///   - sourceAppBundleID: The bundle ID of the app that opened the URL, if known.
    /// - Returns: `true` if the URL was handled by a custom rule, `false` for default behavior.
    @discardableResult
    func openExternal(_ url: URL, from sourceAppBundleID: String? = nil) -> Bool {
        let externalSettings = settings.privacyProtection.externalURLSettings
        let privacySettings = settings.privacyProtection

        // Clean URL before processing (respects privacy settings)
        let cleanedURL: URL = {
            guard privacySettings.enableLinkProtection,
                  !OAuthDomainRegistry.shouldBypassPrivacyProtection(url),
                  let cleaned = LinkProtection.cleanURL(from: url)
            else {
                return url
            }
            return cleaned
        }()

        // Resolve the action based on rules
        let action = externalSettings.resolve(url: cleanedURL, sourceAppBundleID: sourceAppBundleID)

        // Execute the action
        return execute(action, url: cleanedURL, activate: externalSettings.activateOnExternalURL)
    }

    // MARK: - Execution

    /// Executes an external URL action.
    ///
    /// - Parameters:
    ///   - action: The action to execute.
    ///   - url: The URL to open.
    ///   - activate: Whether to activate Refrax.
    /// - Returns: `true` if the action was handled, `false` for default behavior.
    private func execute(_ action: ExternalURLAction, url: URL, activate: Bool) -> Bool {
        switch action {
        case .default:
            return false

        case .openInCurrentSpace:
            openInCurrentSpace(url: url, activate: activate)
            return true

        case .openInGlimpse:
            windowManager.createGlimpseWindow(url: url)
            if activate {
                NSApp.activate(ignoringOtherApps: true)
            }
            return true

        case let .openInSpace(spaceID):
            openInSpace(spaceID, url: url, activate: activate)
            return true

        case let .openInGroup(spaceID, groupID):
            openInGroup(spaceID: spaceID, groupID: groupID, url: url, activate: activate)
            return true

        case .block:
            Logger.info("Blocked external URL: \(url)", category: Logger.navigation)
            return true
        }
    }

    // MARK: - Action Implementations

    private func openInCurrentSpace(url: URL, activate: Bool) {
        // Find frontmost window or create one
        let controller = windowManager.frontmostWindowController
            ?? windowManager.lastActiveBrowserWindowController
            ?? windowManager.createWindow()

        let space = controller.windowState.activeSpace ?? tabManager.state.spaces.first
        if let space {
            tabManager.createTab(url: url, in: space, makeActive: true, loadImmediately: true)
        }

        if activate {
            NSApp.activate(ignoringOtherApps: true)
            controller.window?.makeKeyAndOrderFront(nil)
        }
    }

    private func openInSpace(_ spaceID: UUID, url: URL, activate: Bool) {
        guard let space = tabManager.state.spaces.first(where: { $0.id == spaceID }) else {
            Logger.warning(
                "External URL rule target space \(spaceID) not found, falling back to current space",
                category: Logger.navigation,
            )
            openInCurrentSpace(url: url, activate: activate)
            return
        }

        tabManager.createTab(url: url, in: space, makeActive: true, loadImmediately: true)

        // Switch to the target space's window if needed
        if let controller = windowManager.windowController(for: space) {
            if activate {
                NSApp.activate(ignoringOtherApps: true)
                controller.window?.makeKeyAndOrderFront(nil)
            }
            controller.windowState.setActiveSpace(space)
        } else if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func openInGroup(spaceID: UUID, groupID: UUID, url: URL, activate: Bool) {
        guard let space = tabManager.state.spaces.first(where: { $0.id == spaceID }) else {
            Logger.warning(
                "External URL rule target space \(spaceID) not found",
                category: Logger.navigation,
            )
            openInCurrentSpace(url: url, activate: activate)
            return
        }

        let targetGroupID: UUID? = space.groups.contains { $0.id == groupID } ? groupID : nil

        if targetGroupID == nil {
            Logger.warning(
                "External URL rule target group \(groupID) not found, opening in space",
                category: Logger.navigation,
            )
        }

        tabManager.createTab(
            url: url,
            in: space,
            groupID: targetGroupID,
            makeActive: true,
            loadImmediately: true,
        )

        // Switch to the target space in a window
        let controller = windowManager.windowController(for: space)
            ?? windowManager.frontmostWindowController
            ?? windowManager.createWindow()

        if activate {
            NSApp.activate(ignoringOtherApps: true)
            controller.window?.makeKeyAndOrderFront(nil)
        }
        controller.windowState.setActiveSpace(space)
    }
}

// MARK: - Source App Detection

extension ExternalURLHandler {
    /// Detects the source application that triggered the URL open.
    ///
    /// This should be called before Refrax activates to get accurate results.
    /// Once Refrax is frontmost, the frontmost app will be Refrax itself.
    ///
    /// - Returns: The bundle ID of the frontmost app, or `nil` if detection fails.
    static func detectSourceApp() -> String? {
        // Get the frontmost app before Refrax activates
        // This must be called synchronously before NSApp.activate()
        let frontmostApp = NSWorkspace.shared.frontmostApplication

        // Don't return Refrax's own bundle ID
        let refraxBundleID = Bundle.main.bundleIdentifier
        if frontmostApp?.bundleIdentifier == refraxBundleID {
            return nil
        }

        return frontmostApp?.bundleIdentifier
    }
}
