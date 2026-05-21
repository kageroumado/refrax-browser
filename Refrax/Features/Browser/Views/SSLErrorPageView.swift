import SwiftData
import SwiftUI

/// Displays detailed SSL/TLS certificate error information.
///
/// `SSLErrorPageView` provides a security-focused error display with:
/// - Clear visual indication of the security issue
/// - Detailed explanation of the certificate problem
/// - Certificate chain information when available
/// - Option to proceed (if settings allow and error type permits)
/// - Option to go back safely
///
/// ## Security Design
///
/// This view follows security best practices:
/// - Bypass is disabled by default (requires `BrowserSettings.allowSSLCertificateBypass`)
/// - Revoked certificates can never be bypassed
/// - URL validation ensures bypass only applies to the specific domain
/// - Clear warnings about the risks of proceeding
///
/// ## References
///
/// - [Apple: Preventing Insecure Network Connections](https://developer.apple.com/documentation/security/preventing_insecure_network_connections)
/// - [OWASP: Certificate Pinning](https://owasp.org/www-community/controls/Certificate_and_Public_Key_Pinning)
struct SSLErrorPageView: View {
    @Environment(WindowState.self) private var windowState
    @Environment(TabManager.self) private var tabManager
    @Environment(\.modelContext) private var modelContext

    let errorType: SSLErrorType
    let failedURL: URL

    @State private var showAdvancedInfo = false
    @State private var showCopiedToast = false

    /// Whether SSL bypass is allowed in settings.
    private var bypassAllowed: Bool {
        let settings = BrowserSettings.fetch(in: modelContext)
        return settings.allowSSLCertificateBypass
    }

    /// Whether this specific error type can be bypassed.
    private var canBypass: Bool {
        bypassAllowed && errorType.allowsBypass
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Security warning header
                warningHeader

                // Error explanation
                errorExplanation

                // Advanced info (expandable)
                if showAdvancedInfo {
                    advancedInfoSection
                }

                // Actions
                actionButtons
            }
            .padding(40)
            .frame(maxWidth: 600)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .overlay(alignment: .top) {
            if showCopiedToast {
                copiedToast
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCopiedToast)
        .animation(.easeInOut(duration: 0.3), value: showAdvancedInfo)
    }

    // MARK: - Header

    private var warningHeader: some View {
        VStack(spacing: 16) {
            // Warning icon
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
            }

            // Title
            Text("Your connection is not private")
                .font(.title)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            // Subtitle with error type
            Text(errorType.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Explanation

    private var errorExplanation: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Main warning
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.red)
                    .font(.title3)

                Text("Attackers might be trying to steal your information from **\(failedURL.host ?? "this site")** (for example, passwords, messages, or credit cards).")
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

            // Detailed explanation
            Text(errorType.description)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // URL display
            GroupBox {
                HStack {
                    Image(systemName: "link")
                        .foregroundStyle(.tertiary)

                    Text(failedURL.absoluteString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .truncationMode(.middle)

                    Spacer()

                    Button {
                        copyErrorDetails()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy details")
                }
            }

            // Toggle for advanced info
            Button {
                showAdvancedInfo.toggle()
            } label: {
                HStack {
                    Text(showAdvancedInfo ? "Hide advanced info" : "Show advanced info")
                    Image(systemName: showAdvancedInfo ? "chevron.up" : "chevron.down")
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Advanced Info

    private var advancedInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Technical Details")
                .font(.headline)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    infoRow(label: "Error Type", value: errorType.rawValue)
                    infoRow(label: "Host", value: failedURL.host ?? "Unknown")
                    infoRow(label: "Port", value: "\(failedURL.port ?? 443)")

                    Divider()

                    Text("What this means:")
                        .font(.subheadline.weight(.medium))

                    Text(technicalExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Certificate chain would go here if available
            // certificateChainSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }

    private var technicalExplanation: String {
        switch errorType {
        case .expired:
            "The certificate's validity period has ended. Check if your system date/time is correct."
        case .notYetValid:
            "The certificate's \"Not Before\" date is in the future. Verify your system clock."
        case .hostnameMismatch:
            "The certificate's Subject Alternative Name (SAN) or Common Name (CN) doesn't match the requested hostname."
        case .selfSigned:
            "The certificate was signed by its own private key, not by a trusted Certificate Authority."
        case .revoked:
            "The certificate appears on the Certificate Revocation List (CRL) or failed OCSP verification."
        case .untrustedRoot:
            "The certificate chain leads to a root CA not in the system trust store."
        case .unknown:
            "The Security framework returned an error during trust evaluation."
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 16) {
            // Primary action: Go back
            Button {
                goBack()
            } label: {
                Label("Go Back to Safety", systemImage: "chevron.left")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Secondary action: Proceed (if allowed)
            if canBypass {
                Button {
                    proceedAnyway()
                } label: {
                    Text("Proceed to \(failedURL.host ?? "site") (unsafe)")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .foregroundStyle(.red)
            } else if !errorType.allowsBypass {
                // Revoked certificate - cannot proceed
                Text("This certificate has been revoked. You cannot proceed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Bypass disabled in settings
                Text("Certificate bypass is disabled in settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Toast

    private var copiedToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Error details copied")
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 16)
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
        Task {
            // Approve the SSL bypass through the tab manager and wait for it
            // to ensure the bypass is registered before navigation starts
            await tabManager.approveSSLBypass(for: failedURL)

            // Now reload the URL - the navigation decider will see the bypass approval
            windowState.activeWebPage?.load(failedURL)
        }
    }

    private func copyErrorDetails() {
        let details = """
        SSL Certificate Error
        ---------------------
        Error Type: \(errorType.title) (\(errorType.rawValue))
        URL: \(failedURL.absoluteString)
        Host: \(failedURL.host ?? "Unknown")
        Time: \(Date().formatted())
        
        Description:
        \(errorType.description)
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(details, forType: .string)

        showCopiedToast = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showCopiedToast = false
        }
    }
}

// MARK: - Preview

#Preview("Expired Certificate", traits: .modifier(RefraxPreviewModifier())) {
    SSLErrorPageView(
        errorType: .expired,
        failedURL: URL.staticRequired("https://expired.badssl.com/"),
    )
}

#Preview("Self-Signed Certificate", traits: .modifier(RefraxPreviewModifier())) {
    SSLErrorPageView(
        errorType: .selfSigned,
        failedURL: URL.staticRequired("https://self-signed.badssl.com/"),
    )
}

#Preview("Revoked Certificate", traits: .modifier(RefraxPreviewModifier())) {
    SSLErrorPageView(
        errorType: .revoked,
        failedURL: URL.staticRequired("https://revoked.badssl.com/"),
    )
}
