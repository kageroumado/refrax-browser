import SwiftUI

/// Displays a Focus Mode blocking interstitial when navigating to a restricted domain.
///
/// `FocusBlockedPageView` shows when the user attempts to navigate to a domain
/// that is blocked by the current Focus Mode configuration. It provides:
/// - Clear indication that Focus Mode is blocking the site
/// - The name of the active Focus Mode
/// - Option to go back to the previous page
/// - Option to proceed anyway (adds to session bypass)
///
/// ## Design
///
/// The view uses a friendly but firm tone - Focus Mode is about productivity,
/// not security, so the messaging is less alarming than SSL errors.
struct FocusBlockedPageView: View {
    @Environment(WindowState.self) private var windowState

    let blockedURL: URL
    let focusName: String

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Focus Mode header
                focusHeader

                // Explanation
                explanation

                // Actions
                actionButtons
            }
            .padding(40)
            .frame(maxWidth: 500)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Header

    private var focusHeader: some View {
        VStack(spacing: 16) {
            // Focus icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
            }

            // Title
            Text("\(focusName) is Active")
                .font(.title)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            // Subtitle
            Text("This site is restricted during focus time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Explanation

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 16) {
            // URL display
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundStyle(.tertiary)

                        Text(blockedURL.host ?? blockedURL.absoluteString)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }

                    if !blockedURL.path.isEmpty, blockedURL.path != "/" {
                        Text(blockedURL.path)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Helpful message
            Text("You've configured \(focusName) to restrict access to this site. This helps you stay focused and avoid distractions.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionButtons: some View {
        VStack(spacing: 16) {
            // Primary action: Go back
            Button {
                goBack()
            } label: {
                Label("Go Back", systemImage: "chevron.left")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Secondary action: Proceed anyway
            Button {
                proceedAnyway()
            } label: {
                Text("Proceed Anyway")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .foregroundStyle(.orange)

            // Hint
            Text("Bypassing this restriction will allow access to \(blockedURL.host ?? "this site") until Focus Mode changes.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

    private func goBack() {
        if windowState.activeWebPage?.canGoBack == true {
            windowState.activeWebPage?.goBack()
        } else {
            // Navigate to a safe page if no history
            windowState.activeWebPage?.load(URL.staticRequired("https://duckduckgo.com"))
        }
    }

    private func proceedAnyway() {
        // Add to session bypass
        if let host = blockedURL.host {
            RestrictionEnforcer.shared.addBypassForSession(domain: host)
        }

        // Load the originally blocked URL
        windowState.activeWebPage?.load(blockedURL)
    }
}

// MARK: - Preview

#Preview("Focus Blocked - Reddit", traits: .modifier(RefraxPreviewModifier())) {
    FocusBlockedPageView(
        blockedURL: URL.staticRequired("https://www.reddit.com/r/programming"),
        focusName: "Work",
    )
}

#Preview("Focus Blocked - Twitter", traits: .modifier(RefraxPreviewModifier())) {
    FocusBlockedPageView(
        blockedURL: URL.staticRequired("https://twitter.com/user/status/123"),
        focusName: "Deep Work",
    )
}
