import SwiftUI

// MARK: - Browser Behaviors Modifier

/// Applies standard browser interaction behaviors to a web view.
///
/// Configures:
/// - Find-in-page navigator (Cmd+F)
/// - Link preview on hover
/// - Swipe gestures for back/forward navigation
/// - Text selection
/// - Element fullscreen (videos, etc.)
struct BrowserBehaviorsModifier: ViewModifier {
    @Binding var findNavigatorPresented: Bool

    func body(content: Content) -> some View {
        content
            .webViewFindNavigator(isPresented: $findNavigatorPresented)
            .browserBehaviors()
    }
}

// MARK: - Focus Blur Modifier

/// Shows a blur overlay for domains restricted by Focus Mode.
///
/// When Focus Mode is active with blurred domains configured, this modifier
/// overlays blurred content until the user explicitly reveals it.
struct FocusBlurModifier: ViewModifier {
    let page: WebPage

    /// When false, the overlay is suppressed (e.g. during layout mode).
    var isEnabled: Bool = true

    @State private var isBlurred = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isEnabled, isBlurred, let host = page.url?.host {
                    FocusBlurOverlayView(domain: host) {
                        revealContent()
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                }
            }
            .onChange(of: page.url, initial: true) {
                checkBlurState()
            }
            .onChange(of: RestrictionEnforcer.shared.blurredDomains) {
                checkBlurState()
            }
    }

    private func checkBlurState() {
        guard let host = page.url?.host else {
            isBlurred = false
            return
        }
        isBlurred = RestrictionEnforcer.shared.shouldBlur(domain: host)
    }

    private func revealContent() {
        guard let host = page.url?.host else { return }
        RestrictionEnforcer.shared.markDomainRevealed(domain: host)
        withAnimation(.easeInOut(duration: 0.2)) {
            isBlurred = false
        }
    }
}

// MARK: - Time Limit Modifier

/// Shows an overlay when the domain's daily time limit has been exceeded.
///
/// When users configure time limits for specific domains, this modifier
/// tracks time spent and displays a blocking overlay when limits are reached.
/// Users can snooze the limit (up to 3 times per day) or close the tab.
///
/// Observation is structured to minimize re-renders:
/// - The modifier only observes `isCurrentDomainLimitExceeded`
/// - Detailed state (timeSpent, limit) is observed only in the overlay view
struct TimeLimitModifier: ViewModifier {
    let page: WebPage

    /// When false, the overlay is suppressed (e.g. during layout mode).
    var isEnabled: Bool = true

    @Environment(BrowserState.self) private var browserState

    func body(content: Content) -> some View {
        let isExceeded = isEnabled && browserState.domainTimeTracker.isCurrentDomainLimitExceeded

        content
            .overlay {
                if isExceeded {
                    TimeLimitOverlayContainer(page: page)
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                }
            }
    }
}

/// Container view that observes detailed time limit state only when limit is exceeded.
///
/// By isolating the detailed observations (timeSpent, limit, domain) here,
/// we prevent the parent WebViewContainer from re-rendering when these values
/// change - only this overlay re-renders.
private struct TimeLimitOverlayContainer: View {
    let page: WebPage

    @Environment(BrowserState.self) private var browserState
    @Environment(TabManager.self) private var tabManager

    var body: some View {
        let tracker = browserState.domainTimeTracker
        let domain = tracker.currentDomain ?? page.url?.registrableDomain ?? "Unknown"
        let timeSpent = tracker.currentDomainTimeToday

        if let limit = tracker.currentDomainLimit {
            TimeLimitOverlayView(
                domain: domain,
                timeSpent: timeSpent,
                timeLimit: TimeInterval(limit.dailyLimitSeconds),
                snoozesRemaining: limit.snoozesRemaining,
                onSnooze: {
                    Task {
                        await tracker.useSnoozeForCurrentDomain()
                    }
                },
                onCloseTab: {
                    closeTab()
                },
            )
        }
    }

    private func closeTab() {
        guard let tab = page.tabPage.tab else { return }
        tabManager.closeTab(tab)
    }
}
