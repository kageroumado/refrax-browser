import CoreGraphics
import Foundation
import SwiftUI

/// App-wide constants for layout, animation, and configuration
enum Constants {
    // MARK: - Layout

    enum Layout {
        static let sidebarMinWidth: CGFloat = 250
        static let sidebarDefaultWidth: CGFloat = 350
        static let sidebarMaxWidth: CGFloat = 600
        static let inspectorMinWidth: CGFloat = 300
        static let inspectorDefaultWidth: CGFloat = 400
        static let inspectorMaxWidth: CGFloat = 600
        static let tabItemHeight: CGFloat = 36
        static let toolbarHeight: CGFloat = 48
        static let toolbarMargin: CGFloat = 16
        static let toolbarCornerRadius: CGFloat = 12
        static let cardCornerRadius: CGFloat = 8
        static let windowMinWidth: CGFloat = 800
        static let windowMinHeight: CGFloat = 600
        static let windowDefaultWidth: CGFloat = 1_920
        static let windowDefaultHeight: CGFloat = 1_080
        static let trafficLightOffsetX: CGFloat = 20
        static let trafficLightOffsetY: CGFloat = 24
        static let nestingLevelPadding: CGFloat = 16
        
        // Tab list specific
        static let tabSpacing: CGFloat = 4 // Vertical spacing between tabs
        static let pinnedUnpinnedSpacing: CGFloat = 12 // Extra spacing between pinned/unpinned sections
        static let pinnedBackgroundCornerRadius: CGFloat = 16
        static let tabFaviconSize: CGFloat = 24
        static let tabButtonVisibleSize: CGFloat = 20
        static let tabButtonHitTargetSize: CGFloat = 24
        
        // Sidebar container and padding
        static let sidebarCornerRadius: CGFloat = 18 // Main sidebar container corner radius
        static let sidebarPadding: CGFloat = 8 // Padding between sidebar edge and pinned background
        static let tabHorizontalPadding: CGFloat = sidebarPadding
        static let tabCornerRadius: CGFloat = sidebarCornerRadius - sidebarPadding
    }

    // MARK: - Animation

    enum Animation {
        static let springDuration: TimeInterval = 0.3
        static let springDamping: CGFloat = 0.8
        static let hoverDuration: TimeInterval = 0.1
        static let dragSpringDuration: TimeInterval = 0.4
        static let dragSpringDamping: CGFloat = 0.7
        static let modalSpringDuration: TimeInterval = 0.5
        static let modalSpringDamping: CGFloat = 0.85

        // Tab drag specific
        static let dragReturnResponse: CGFloat = 0.28
        static let dragReturnDamping: CGFloat = 0.9
        static let dragReorderResponse: CGFloat = 0.32
        static let dragReorderDamping: CGFloat = 0.88
        static let dragCleanupDelay: TimeInterval = 0.3

        /// Delay before triggering auto-rename after item creation.
        /// Matches spring animation duration to ensure view is fully visible.
        static let renameDelay: Duration = .milliseconds(Int(springDuration * 1_000))
    }
    
    // MARK: - Tab Drag Behavior
    
    enum TabDrag {
        /// Percentage of row height a tab must be dragged before swapping positions
        static let swapThreshold: CGFloat = 0.66
        
        /// Percentage of row height where neighbor tabs start being pushed aside
        static let neighborPushThreshold: CGFloat = 0.40
        
        /// Drag threshold when no pinned tabs exist (requires more commitment)
        static let pinThresholdNoPinnedTabs: CGFloat = 0.5
        
        /// Drag threshold when pinned tabs already exist (more responsive)
        static let pinThresholdWithPinnedTabs: CGFloat = 0.33
        
        /// Minimum distance in points before drag gesture activates
        static let minimumDragDistance: CGFloat = 5
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
    }

    enum AddressBar {
        static let height = 32.0
        static let buttonHeight = 28.0
        static let buttonWidth = 20.0
        static let buttonFontSize = 12.0
        static let zoomLevels = [50, 75, 85, 100, 115, 125, 150, 175, 200, 250, 300]
    }

    // MARK: - Sidebar Animation

    enum SidebarAnimation {
        /// Width of compact sidebar mode strip
        static let compactWidth: CGFloat = 48

        /// Width used for activation zone
        static let activationWidth: CGFloat = 40

        /// Tolerance period before hiding sidebar after mouse exit
        static let mouseExitTolerance: Duration = .milliseconds(300)

        /// Progress threshold that triggers snap-to-visible animation
        static let snapThreshold: CGFloat = 0.5

        /// Padding around the glass effect
        static let glassEffectPadding: CGFloat = 8

        /// Corner radius for the glass effect
        static let glassCornerRadius: CGFloat = 18

        /// Duration for snap-to-visible easeInOut animation
        static let snapDuration: CGFloat = 0.25

        /// Spring animation parameters for hide
        static let hideSpringResponse: CGFloat = 0.3
        static let hideSpringDamping: CGFloat = 0.7

        /// Spring animation parameters for cancel
        static let cancelSpringResponse: CGFloat = 0.25
        static let cancelSpringDamping: CGFloat = 0.65

        /// Cubic ease-in exponent for follow-cursor animation
        static let easeInExponent: CGFloat = 3.0

        // MARK: Tutorial Peek Animation

        /// Delay before showing tutorial peek after sidebar collapse
        static let tutorialPeekDelay: Duration = .milliseconds(600)

        /// Duration of the peek animation (move in)
        static let tutorialPeekInDuration: CGFloat = 0.6

        /// How far the sidebar peeks in (pixels from edge)
        static let tutorialPeekDistance: CGFloat = 60

        /// How long to hold the peek before hiding
        static let tutorialPeekHoldDuration: Duration = .milliseconds(600)

        /// Duration of the peek hide animation
        static let tutorialPeekOutDuration: CGFloat = 0.6

        // MARK: Compact Mode Traffic Lights

        /// Scale factor for traffic lights in compact mode (tiny state)
        static let compactTrafficLightScale: CGFloat = 0.42

        /// Horizontal translation offset to compensate for scale and center in sidebar
        static let compactTrafficLightTranslateX: CGFloat = 12

        /// Vertical translation offset
        static let compactTrafficLightTranslateY: CGFloat = 18

        /// Padding for compact traffic light platter
        static let compactTrafficLightPadding: CGFloat = 8

        /// Duration for traffic light scale animations
        static let compactTrafficLightAnimationDuration: CGFloat = 0.2
    }

    // MARK: - Detail Tray Animation

    enum DetailTray {
        /// Width of the detail tray panel
        static let width: CGFloat = 280

        /// Gap constant for expanded sidebar (produces 16px visual gap after glass padding math)
        /// Formula: newLeading = sidebarTrailing + gap - glassPadding
        /// Accounts for sidebar's extra structure (concentricity, glass padding)
        static let gapFromExpandedSidebar: CGFloat = 24

        /// Gap constant for collapsed sidebar with overlay (produces 8px visual gap)
        /// Overlay has simpler glass structure, so direct: gap = desired visual gap
        static let gapFromOverlay: CGFloat = 8

        /// Duration for show animation
        static let showDuration: CGFloat = 0.25

        /// Duration for hide animation
        static let hideDuration: CGFloat = 0.2

        /// Duration for position update animation when sidebar state changes
        static let repositionDuration: CGFloat = 0.2

        /// Corner radius for the glass effect (matches sidebar)
        static let glassCornerRadius: CGFloat = 18

        /// Padding around the glass effect (matches sidebar)
        static let glassEffectPadding: CGFloat = 8

        /// Tolerance period before hiding tray after mouse exit
        static let mouseExitTolerance: Duration = .milliseconds(400)
    }
}

/// macOS virtual key codes for keyboard event handling.
enum KeyCode {
    static let tab: UInt16 = 48
    static let escape: UInt16 = 53
    static let backspace: UInt16 = 51
    static let forwardDelete: UInt16 = 117
}
