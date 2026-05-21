import SwiftUI

/// Displays a crash error page when a web content process terminates
/// and auto-recovery is suppressed.
///
/// Shown when:
/// - The page exceeds the crash threshold (e.g., 3 crashes in 60 seconds)
/// - Automatic crash recovery is disabled in settings
///
/// Provides the user with:
/// - Clear indication of what happened (crash reason)
/// - Technical details (crash count, termination reason)
/// - Actionable retry button that resets crash tracking
struct CrashPageView: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(WebPagePool.self) private var pagePool

    let page: WebPage
    let crashError: CrashError

    @State private var toastMessage: String?
    @State private var isCompact = false

    private enum Layout {
        static let compactWidthThreshold: CGFloat = 450
        static let compactHeightThreshold: CGFloat = 600
        static let fullMaxWidth: CGFloat = 600
        static let compactMaxWidth: CGFloat = 380
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                crashContent
                    .padding(24)
                    .frame(maxWidth: isCompact ? Layout.compactMaxWidth : Layout.fullMaxWidth)
                    .frame(maxWidth: .infinity)
            }
            .onChange(of: geometry.size, initial: true) { _, newSize in
                isCompact = newSize.width < Layout.compactWidthThreshold
                    || newSize.height < Layout.compactHeightThreshold
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .overlay(alignment: .top) {
            if let message = toastMessage {
                copiedToast(message: message)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastMessage)
    }

    // MARK: - Content

    private var crashContent: some View {
        VStack(spacing: 24) {
            crashHeader
            crashExplanation
            resolutionSection
            actionButtons
        }
    }

    // MARK: - Header

    private var crashHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: crashInfo.icon)
                .font(.system(size: isCompact ? 48 : 64))
                .foregroundStyle(crashInfo.color.gradient)

            Text(crashInfo.title)
                .font(isCompact ? .title2 : .largeTitle)
                .fontWeight(.semibold)

            Text(crashInfo.subtitle)
                .font(isCompact ? .caption : .body)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Explanation

    private var crashExplanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What happened?")
                .font(isCompact ? .subheadline : .title3)
                .fontWeight(.semibold)

            Text(crashInfo.explanation)
                .font(isCompact ? .subheadline : .body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            urlField

            Button {
                copyErrorDetails()
            } label: {
                Label("Copy Error Details", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .font(isCompact ? .caption : .body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var urlField: some View {
        GroupBox {
            HStack(spacing: 12) {
                Text(crashError.url.absoluteString)
                    .font(.system(isCompact ? .caption2 : .subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer()

                AddressBarCopyLinkButton(
                    copyURL: copyURL,
                    copyMarkdown: copyMarkdownLink
                )
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Resolution

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What can you try?")
                .font(isCompact ? .subheadline : .title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(crashInfo.suggestions, id: \.self) { suggestion in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.green)
                            .font(isCompact ? .subheadline : .body)

                        Text(suggestion)
                            .font(isCompact ? .subheadline : .body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private var canGoBack: Bool {
        page.canGoBack
    }

    private var isMultiPageTab: Bool {
        (page.tabPage.tab?.pages.count ?? 1) > 1
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if canGoBack {
                Button {
                    page.goBack()
                } label: {
                    Label("Go Back", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(isCompact ? .regular : .large)
            } else {
                Button {
                    closeTabOrPage()
                } label: {
                    Label(
                        isMultiPageTab ? "Close Page" : "Close Tab",
                        systemImage: "xmark"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(isCompact ? .regular : .large)
            }

            Button {
                retry()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(isCompact ? .regular : .large)
        }
    }

    // MARK: - Toast

    private func copiedToast(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 16)
    }

    // MARK: - Actions

    private func retry() {
        // Reset crash tracking so the next crash doesn't immediately suppress recovery
        pagePool.clearProblematicState(for: page.tabPage.id)
        // Reload the page (startNewNavigation clears crashError)
        page.load(crashError.url)
    }

    private func closeTabOrPage() {
        guard let tab = page.tabPage.tab else { return }

        if isMultiPageTab {
            tabManager.removePageFromTab(tab, page: page.tabPage)
        } else {
            tabManager.closeTab(tab)
        }
    }

    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(crashError.url.absoluteString, forType: .string)
        showToast("URL copied")
    }

    private func copyMarkdownLink() {
        let title = page.tabPage.title.isEmpty ? "Crashed page" : page.tabPage.title
        let markdown = "[\(title)](\(crashError.url.absoluteString))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        showToast("Markdown link copied")
    }

    private func copyErrorDetails() {
        let details = """
        Error: Web content process \(crashError.reason.userDescription)
        URL: \(crashError.url.absoluteString)
        Crashes: \(crashError.crashCount) in recent window
        Reason: \(crashError.reason.logDescription)
        Time: \(crashError.timestamp.formatted())
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(details, forType: .string)
        showToast("Error details copied")
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            toastMessage = nil
        }
    }

    // MARK: - Crash Information

    private var crashInfo: CrashInfo {
        CrashInfo.info(for: crashError)
    }
}

// MARK: - Crash Information

private struct CrashInfo {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let explanation: String
    let suggestions: [String]

    static func info(for error: CrashError) -> CrashInfo {
        switch error.reason {
        case .exceededMemoryLimit:
            return CrashInfo(
                title: "Page Ran Out of Memory",
                subtitle: "The web process was terminated by the system",
                icon: "memorychip.fill",
                color: .orange,
                explanation: "This page used too much memory and was terminated by the system to protect your Mac's performance. This often happens with pages that load very large amounts of data, have memory leaks, or run intensive JavaScript.",
                suggestions: [
                    "Close other tabs to free up memory",
                    "Try reloading — the issue may be temporary",
                    "Check if the page has a lighter or mobile version",
                    "Disable extensions that might increase memory usage",
                ]
            )

        case .exceededCPULimit:
            return CrashInfo(
                title: "Page Used Too Much CPU",
                subtitle: "The web process was terminated by the system",
                icon: "cpu.fill",
                color: .orange,
                explanation: "This page was using excessive CPU resources and was terminated to prevent it from slowing down your Mac. This can happen with pages running heavy animations, crypto miners, or poorly optimized scripts.",
                suggestions: [
                    "Try reloading — the issue may be temporary",
                    "Check if content blockers are enabled for this site",
                    "The site may be running resource-intensive scripts",
                    "Try the page in a different browser to confirm the issue",
                ]
            )

        case .crash, .exceededSharedProcessCrashLimit:
            let crashCountText = error.crashCount > 1
                ? "It crashed \(error.crashCount) times recently, so automatic recovery was stopped."
                : "Automatic recovery was not attempted."
            return CrashInfo(
                title: "This Page Crashed",
                subtitle: error.crashCount > 1
                    ? "Crashed \(error.crashCount) times — auto-recovery stopped"
                    : "The web process terminated unexpectedly",
                icon: "exclamationmark.triangle.fill",
                color: .red,
                explanation: "The web content process terminated unexpectedly. \(crashCountText) This can happen due to bugs in the website's code, incompatible browser extensions, or issues with specific web technologies.",
                suggestions: [
                    "Try reloading — the crash may have been a one-time event",
                    "Disable extensions for this site to rule out conflicts",
                    "Clear the site's data and cookies",
                    "If the problem persists, the website may have a bug",
                ]
            )

        case .requestedByClient:
            return CrashInfo(
                title: "Page Was Stopped",
                subtitle: "The web process was intentionally terminated",
                icon: "stop.circle.fill",
                color: .gray,
                explanation: "The web content process was intentionally stopped. This can happen when the system needs to reclaim resources or during browser maintenance operations.",
                suggestions: [
                    "Try reloading the page",
                    "This is usually a temporary condition",
                ]
            )

        @unknown default:
            return CrashInfo(
                title: "Page Process Ended",
                subtitle: "The web process terminated unexpectedly",
                icon: "exclamationmark.triangle.fill",
                color: .red,
                explanation: "The web content process ended for an unknown reason. Try reloading the page.",
                suggestions: [
                    "Try reloading the page",
                    "If the problem persists, try closing and reopening the tab",
                ]
            )
        }
    }
}
