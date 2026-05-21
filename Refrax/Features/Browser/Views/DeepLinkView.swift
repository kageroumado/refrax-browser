import SwiftUI

/// Renders in-tab interstitial views for deep links.
///
/// Handles `refrax://ssl-error` and `refrax://focus-blocked`.
struct DeepLinkView: View {
    let deepLink: DeepLink

    var body: some View {
        content
            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
    }

    @ViewBuilder
    private var content: some View {
        switch deepLink {
        case let .sslError(errorType, failedURL):
            SSLErrorPageView(errorType: errorType, failedURL: failedURL)
        case let .focusBlocked(blockedURL, focusName):
            FocusBlockedPageView(blockedURL: blockedURL, focusName: focusName)
        }
    }
}
