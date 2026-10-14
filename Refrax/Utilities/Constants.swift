import CoreGraphics
import Foundation
import SwiftUI

/// App-wide constants for layout, animation, and configuration
enum Constants {
    // MARK: - Layout

    enum Layout {
        static let tabItemHeight: CGFloat = 36
        /// The smallest the page area of a browser window gets, in both directions
        static let contentMinSize: CGFloat = 400
    }

    // MARK: - URL

    enum URL {
        static let defaultHomepage = "https://www.apple.com"
        static let newTabPage = "refrax://newtab"
        static let emptyPage = "about:blank"
    }

    // MARK: - Spacing

    enum Spacing {
        /// 4 px
        static let xSmall: CGFloat = 4
        /// 6 px - Used for tab content padding
        static let small2: CGFloat = 6
        /// 8 px
        static let small: CGFloat = 8
        /// 16 px
        static let medium: CGFloat = 16 // 4 units
        /// 24 px
        static let large: CGFloat = 24 // 6 units
        /// 32 px
        static let xLarge: CGFloat = 32 // 8 units
    }

    // MARK: - Typography

    enum Typography {
        static let headerSize: CGFloat = 17
        static let headerSizeLarge: CGFloat = 20
        static let bodySize: CGFloat = 13
        static let bodyMediumSize: CGFloat = 14
        static let bodyLargeSize: CGFloat = 15
        static let captionSize: CGFloat = 11
        static let monoSize: CGFloat = 13
    }

    // MARK: - Opacity

    enum Opacity {
        static let tabDefault: Double = 0.6
        static let tabHover: Double = 0.8
        static let tabSelected: Double = 1.0
        static let glassOverlay: Double = 0.1
        static let border: Double = 0.2
        static let toolbarBackground: Double = 0.8
        static let blurAmount: Double = 0.6
        static let tintOpacityMultiplier = 0.25
    }

    // MARK: - App Info

    nonisolated enum App: Sendable {
        static let bundleID = "website.refrax.browser"
        static let name = "Refrax"
        static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        static let contentRuleListID = "refrax_content_rule_list"
        static let thirdPartyCookieRuleListID = "refrax_third_party_cookie_blocking"
        static let gpcMessageHandlerName = "refraxGPC"
        static let credentialSubmitHandlerName = "refraxCredentialSubmit"
        static let autoFillFocusHandlerName = "refraxAutoFillFocus"
    }

    /// Backend service endpoints.
    ///
    /// ## Update Channels
    ///
    /// The active ``UpdateChannel`` is selected at compile time:
    /// - **Production** (release builds): GitHub Releases
    /// - **Localhost** (debug builds): Local dev server at `localhost:8080`,
    ///   with ``UpdateChannel/forceUpdate`` enabled (skips version comparison)
    nonisolated enum API: Sendable {
        /// Update distribution channel.
        ///
        /// Determines which server the app checks for updates.
        enum UpdateChannel: Sendable {
            /// GitHub Releases (release builds).
            case production
            /// Local development server for testing (debug builds).
            case localhost

            /// Localhost channel skips version comparison for force-update testing.
            var forceUpdate: Bool {
                self == .localhost
            }
        }

        #if DEBUG
            static let channel: UpdateChannel = .localhost
        #else
            static let channel: UpdateChannel = .production
        #endif

        /// The local dev server's update manifest, used by the localhost channel.
        private static let localhostReleasesLatest = Foundation.URL(string: "http://localhost:8080/api/releases/latest")!

        /// GitHub repository serving release builds and update checks.
        static let githubRepo = "kageroumado/refrax-browser"

        /// Update-check endpoint.
        ///
        /// Release builds check GitHub Releases — public, tokenless, so
        /// open-source builds get updates too. The localhost debug channel
        /// keeps the self-hosted JSON shape for force-update testing.
        static var releasesLatest: Foundation.URL? {
            if channel.forceUpdate {
                return localhostReleasesLatest
            }
            return Foundation.URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")
        }

        /// Hosts an update download (or signature) URL may point at, in
        /// addition to the check endpoint's own host. GitHub release assets
        /// live on `github.com` URLs that redirect to
        /// `objects.githubusercontent.com`.
        static let updateDownloadHosts: Set<String> = [
            "github.com",
            "objects.githubusercontent.com",
        ]

        /// In-app feedback intake, for every build: release, debug and
        /// open-source clones alike.
        static let feedback = Foundation.URL(string: "https://kagerou.glass/api/refrax/feedback")!
    }
    
    /// The page controls of the page card and the address field of Glimpse and Reflected windows.
    enum PageControls {
        static let height = 32.0
        static let buttonHeight = 28.0
        static let buttonWidth = 20.0
        static let buttonFontSize = 12.0
        static let engineBadgeSize = 14.0
        static let zoomLevels = [50, 75, 85, 100, 115, 125, 150, 175, 200, 250, 300]
    }

    // MARK: - Detail Tray Animation

    enum DetailTray {
        /// Width of the detail tray panel
        static let width: CGFloat = 280

        /// Gap between the tray's glass and the window's leading edge
        static let gapFromEdge: CGFloat = 8

        /// Duration for show animation
        static let showDuration: CGFloat = 0.25

        /// Duration for hide animation
        static let hideDuration: CGFloat = 0.2

        /// Corner radius for the glass effect
        static let glassCornerRadius: CGFloat = 18

        /// Padding around the glass effect
        static let glassEffectPadding: CGFloat = 8
    }
}

/// macOS virtual key codes for keyboard event handling.
enum KeyCode {
    static let tab: UInt16 = 48
    static let escape: UInt16 = 53
    static let backspace: UInt16 = 51
    static let forwardDelete: UInt16 = 117
}
