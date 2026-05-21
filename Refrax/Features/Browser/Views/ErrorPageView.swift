import SwiftUI

/// Displays detailed error information for failed navigations.
///
/// `ErrorPageView` provides a user-friendly error display with:
/// - HTTP status code and standardized title
/// - Clear explanation of what went wrong
/// - Actionable resolution suggestions
/// - Option to retry or copy error details
///
/// ## Error Categories
///
/// Errors are grouped by HTTP status code ranges:
/// - **4xx Client Errors**: Issues with the request (not found, forbidden, etc.)
/// - **5xx Server Errors**: Issues on the server side
/// - **Network Errors**: Connection problems (negative codes from URLError)
/// - **SSL/TLS Errors**: Certificate and security issues
///
/// ## Adaptive Layout
///
/// Uses width-based detection to provide full-sized and compact layouts
/// depending on available space (e.g., split view vs full window).
struct ErrorPageView: View {
    @Environment(TabManager.self) private var tabManager

    let page: WebPage
    let statusCode: Int
    let failedURL: URL

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
                errorContent
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

    private var errorContent: some View {
        VStack(spacing: 24) {
            errorHeader
            errorExplanation
            resolutionSection
            actionButtons
        }
    }

    // MARK: - Header

    private var errorHeader: some View {
        VStack(spacing: 12) {
            // Icon with status code overlay
            ZStack {
                Image(systemName: errorInfo.icon)
                    .font(.system(size: isCompact ? 48 : 64))
                    .foregroundStyle(errorInfo.color.gradient)

                if errorInfo.showsCodeBadge {
                    Text("\(statusCode)")
                        .font(.system(size: isCompact ? 12 : 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, isCompact ? 6 : 8)
                        .padding(.vertical, isCompact ? 3 : 4)
                        .background(errorInfo.color, in: Capsule())
                        .offset(x: isCompact ? 24 : 32, y: isCompact ? 18 : 24)
                }
            }

            // Title
            Text(errorInfo.title)
                .font(isCompact ? .title2 : .largeTitle)
                .fontWeight(.semibold)

            // Status code subtitle — show "HTTP" prefix only for HTTP codes
            if statusCode > 0 {
                Text("HTTP \(statusCode)")
                    .font(isCompact ? .caption : .body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Explanation

    private var errorExplanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What happened?")
                .font(isCompact ? .subheadline : .title3)
                .fontWeight(.semibold)

            Text(errorInfo.explanation)
                .font(isCompact ? .subheadline : .body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            // Failed URL with copy button
            urlField

            // Copy error details button
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
                Text(failedURL.absoluteString)
                    .font(.system(isCompact ? .caption2 : .subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer()

                AddressBarCopyLinkButton(
                    copyURL: copyURL,
                    copyMarkdown: copyMarkdownLink,
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
                ForEach(errorInfo.suggestions, id: \.self) { suggestion in
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
                // Go Back on left (matches back button position in address bar)
                Button {
                    goBack()
                } label: {
                    Label("Go Back", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(isCompact ? .regular : .large)
            } else {
                // Close Tab/Page when there's nothing to go back to
                Button {
                    closeTabOrPage()
                } label: {
                    Label(
                        isMultiPageTab ? "Close Page" : "Close Tab",
                        systemImage: "xmark",
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(isCompact ? .regular : .large)
            }

            // Try Again on right (matches reload button position in address bar)
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
        page.load(failedURL)
    }

    private func goBack() {
        page.goBack()
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
        NSPasteboard.general.setString(failedURL.absoluteString, forType: .string)
        showToast("URL copied")
    }

    private func copyMarkdownLink() {
        // Use error title as the link text
        let markdown = "[\(errorInfo.title)](\(failedURL.absoluteString))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        showToast("Markdown link copied")
    }

    private func copyErrorDetails() {
        let prefix = statusCode > 0 ? "HTTP \(statusCode)" : "Error \(statusCode)"
        let details = """
        Error: \(prefix) - \(errorInfo.title)
        URL: \(failedURL.absoluteString)
        Time: \(Date().formatted())
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

    // MARK: - Error Information

    private var errorInfo: ErrorInfo {
        ErrorInfo.info(for: statusCode)
    }
}

// MARK: - Error Information

/// Structured information about HTTP errors.
private struct ErrorInfo {
    let title: String
    let icon: String
    let color: Color
    let explanation: String
    let suggestions: [String]
    let showsCodeBadge: Bool

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    /// Gets error information for a status code.
    static func info(for code: Int) -> ErrorInfo {
        switch code {
        // MARK: - 4xx Client Errors

        case 400:
            return ErrorInfo(
                title: "Bad Request",
                icon: "exclamationmark.circle",
                color: .orange,
                explanation: "The server couldn't understand the request due to invalid syntax or malformed data.",
                suggestions: [
                    "Check if the URL is typed correctly",
                    "Clear your browser cache and cookies",
                    "Try refreshing the page",
                ],
                showsCodeBadge: true,
            )

        case 401:
            return ErrorInfo(
                title: "Authentication Required",
                icon: "person.crop.circle.badge.questionmark",
                color: .blue,
                explanation: "This page requires you to sign in. You may need valid credentials to access this content.",
                suggestions: [
                    "Sign in with your account",
                    "Check if your session has expired",
                    "Verify your credentials are correct",
                ],
                showsCodeBadge: true,
            )

        case 403:
            return ErrorInfo(
                title: "Access Forbidden",
                icon: "lock.circle",
                color: .red,
                explanation: "You don't have permission to access this page. This might be intentional or due to account restrictions.",
                suggestions: [
                    "Check if you're signed in to the correct account",
                    "Contact the site administrator for access",
                    "Verify you have the required permissions",
                ],
                showsCodeBadge: true,
            )

        case 404:
            return ErrorInfo(
                title: "Page Not Found",
                icon: "questionmark.circle",
                color: .gray,
                explanation: "The page you're looking for doesn't exist. It may have been moved, deleted, or the URL might be incorrect.",
                suggestions: [
                    "Check the URL for typos",
                    "Search for the content on the site",
                    "Try the site's homepage",
                    "Use a search engine to find the page",
                ],
                showsCodeBadge: true,
            )

        case 405:
            return ErrorInfo(
                title: "Method Not Allowed",
                icon: "nosign",
                color: .orange,
                explanation: "The request method is not supported for this URL. This is typically a website configuration issue.",
                suggestions: [
                    "Try accessing the page directly instead of through a form",
                    "Clear your browser cache",
                    "Contact the website owner",
                ],
                showsCodeBadge: true,
            )

        case 408:
            return ErrorInfo(
                title: "Request Timeout",
                icon: "clock.badge.exclamationmark",
                color: .orange,
                explanation: "The server took too long to respond. This could be due to network issues or a slow server.",
                suggestions: [
                    "Check your internet connection",
                    "Try again in a few moments",
                    "The server might be experiencing high load",
                ],
                showsCodeBadge: true,
            )

        case 410:
            return ErrorInfo(
                title: "Gone",
                icon: "trash.circle",
                color: .gray,
                explanation: "This content has been permanently removed and is no longer available.",
                suggestions: [
                    "The content is no longer available",
                    "Check if there's an archived version",
                    "Look for updated content on the site",
                ],
                showsCodeBadge: true,
            )

        case 429:
            return ErrorInfo(
                title: "Too Many Requests",
                icon: "speedometer",
                color: .orange,
                explanation: "You've made too many requests in a short time. The server is rate-limiting your access.",
                suggestions: [
                    "Wait a few minutes before trying again",
                    "Reduce the frequency of your requests",
                    "Check if you're behind a VPN or proxy",
                ],
                showsCodeBadge: true,
            )

        case 451:
            return ErrorInfo(
                title: "Unavailable For Legal Reasons",
                icon: "doc.text.magnifyingglass",
                color: .purple,
                explanation: "This content is blocked due to legal restrictions in your region or jurisdiction.",
                suggestions: [
                    "Content may be restricted in your country",
                    "Check your local regulations",
                    "Contact the content provider for more information",
                ],
                showsCodeBadge: true,
            )

        // MARK: - 5xx Server Errors

        case 500:
            return ErrorInfo(
                title: "Internal Server Error",
                icon: "exclamationmark.triangle",
                color: .red,
                explanation: "The server encountered an unexpected error. This is not your fault—it's an issue on the website's end.",
                suggestions: [
                    "Try again in a few minutes",
                    "The website team is likely aware of the issue",
                    "Check the site's status page if available",
                ],
                showsCodeBadge: true,
            )

        case 502:
            return ErrorInfo(
                title: "Bad Gateway",
                icon: "network.slash",
                color: .red,
                explanation: "The server received an invalid response from an upstream server. This is typically a temporary issue.",
                suggestions: [
                    "Wait a few moments and try again",
                    "The issue is usually temporary",
                    "Check if the site is undergoing maintenance",
                ],
                showsCodeBadge: true,
            )

        case 503:
            return ErrorInfo(
                title: "Service Unavailable",
                icon: "server.rack",
                color: .orange,
                explanation: "The server is temporarily unable to handle requests, often due to maintenance or high traffic.",
                suggestions: [
                    "Try again in a few minutes",
                    "The site may be under maintenance",
                    "Check the site's status page or social media",
                ],
                showsCodeBadge: true,
            )

        case 504:
            return ErrorInfo(
                title: "Gateway Timeout",
                icon: "clock.badge.xmark",
                color: .red,
                explanation: "The server didn't receive a timely response from an upstream server.",
                suggestions: [
                    "Check your internet connection",
                    "Try again in a few moments",
                    "The server may be under heavy load",
                ],
                showsCodeBadge: true,
            )

        // MARK: - Network Errors (negative URLError codes)

        case -999:
            return ErrorInfo(
                title: "Page Loading Stopped",
                icon: "stop.circle",
                color: .gray,
                explanation: "The page was not fully loaded before navigation was stopped.",
                suggestions: [
                    "Click \"Try Again\" to reload the page",
                    "Check your internet connection if the page was loading slowly",
                    "The server may be slow or unresponsive",
                ],
                showsCodeBadge: false,
            )

        case -1_001:
            return ErrorInfo(
                title: "Connection Timed Out",
                icon: "clock.badge.exclamationmark",
                color: .orange,
                explanation: "The connection to the server timed out. The server may be unreachable or your network may be blocking the connection.",
                suggestions: [
                    "Check your internet connection",
                    "If you're on a corporate network, check that your VPN is connected",
                    "Check if a firewall or proxy is blocking the connection",
                    "Try again later—the server might be temporarily down",
                ],
                showsCodeBadge: false,
            )

        case -1_003:
            return ErrorInfo(
                title: "Server Not Found",
                icon: "magnifyingglass.circle",
                color: .gray,
                explanation: "The domain name could not be resolved. The address may be misspelled, or the DNS server may be unable to find it.",
                suggestions: [
                    "Check if the URL is spelled correctly",
                    "If you're on a corporate network, check that your VPN is connected",
                    "Try using a different DNS server (e.g., 1.1.1.1 or 8.8.8.8)",
                    "Check your network settings and DNS configuration",
                    "The domain may have expired or been deregistered",
                ],
                showsCodeBadge: false,
            )

        case -1_004:
            return ErrorInfo(
                title: "Can\u{2019}t Connect to the Server",
                icon: "wifi.slash",
                color: .red,
                explanation: "A connection to the server could not be established. The server may be down, or your network may not be able to reach it.",
                suggestions: [
                    "Check your internet connection",
                    "If you're on a corporate network, check that your VPN is connected",
                    "Check if a firewall or security policy is blocking the connection",
                    "Verify the address and port are correct",
                    "Check your network's NAT and routing configuration",
                    "Try again later—the server may be temporarily offline",
                ],
                showsCodeBadge: false,
            )

        case -1_005:
            return ErrorInfo(
                title: "Connection Lost",
                icon: "antenna.radiowaves.left.and.right.slash",
                color: .orange,
                explanation: "The network connection was lost during the request.",
                suggestions: [
                    "Check your Wi-Fi or Ethernet connection",
                    "Move closer to your router if on Wi-Fi",
                    "If you're on a VPN, check that it's still connected",
                    "Try again when you have a stable connection",
                ],
                showsCodeBadge: false,
            )

        case -1_006:
            return ErrorInfo(
                title: "DNS Lookup Failed",
                icon: "network.badge.shield.half.filled",
                color: .orange,
                explanation: "The DNS lookup for this domain failed. Your DNS server could not resolve the address.",
                suggestions: [
                    "Check if the URL is spelled correctly",
                    "Try using a different DNS server (e.g., 1.1.1.1 or 8.8.8.8)",
                    "If you're on a corporate network, check that your VPN is connected",
                    "Your ISP's DNS server may be experiencing issues",
                    "Check your firewall and network policies",
                ],
                showsCodeBadge: false,
            )

        case -1_009:
            return ErrorInfo(
                title: "No Internet Connection",
                icon: "wifi.exclamationmark",
                color: .red,
                explanation: "Your device appears to be offline. Check your internet connection and try again.",
                suggestions: [
                    "Turn Wi-Fi off and on again",
                    "Check if other apps can connect to the internet",
                    "Restart your router if needed",
                    "If you're on a VPN, try disconnecting and reconnecting",
                ],
                showsCodeBadge: false,
            )

        case -1_200:
            return ErrorInfo(
                title: "Secure Connection Failed",
                icon: "lock.trianglebadge.exclamationmark",
                color: .red,
                explanation: "A secure connection could not be established. The site's security certificate may be invalid or expired.",
                suggestions: [
                    "Check if your system date and time are correct",
                    "The site's certificate may have expired",
                    "Proceed with caution if you choose to continue",
                ],
                showsCodeBadge: false,
            )

        case -1_202:
            return ErrorInfo(
                title: "Certificate Invalid",
                icon: "checkmark.seal.text.page.badged.xmark",
                color: .red,
                explanation: "The site's security certificate is not trusted. This could indicate a security risk.",
                suggestions: [
                    "Don't enter sensitive information on this site",
                    "Check if you're on the correct website",
                    "The certificate may be self-signed or expired",
                ],
                showsCodeBadge: false,
            )

        // MARK: - Default

        default:
            let category = errorCategory(for: code)
            return ErrorInfo(
                title: category.title,
                icon: category.icon,
                color: category.color,
                explanation: "An error occurred while loading this page (Error \(code)).",
                suggestions: [
                    "Try refreshing the page",
                    "Check your internet connection",
                    "Try again later",
                ],
                showsCodeBadge: code > 0,
            )
        }
    }

    /// Gets the general category for unknown status codes.
    private static func errorCategory(for code: Int) -> (title: String, icon: String, color: Color) {
        switch code {
        case 400 ..< 500:
            ("Client Error", "exclamationmark.circle", .orange)
        case 500 ..< 600:
            ("Server Error", "exclamationmark.triangle", .red)
        case ..<0:
            ("Network Error", "wifi.slash", .red)
        default:
            ("Error", "xmark.circle", .gray)
        }
    }
}

