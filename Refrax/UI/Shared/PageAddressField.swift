import SwiftUI

/// The address field of a window that shows one page: Glimpse and Reflected windows.
///
/// Back and forward, the engine badge and the page's domain colored by its connection's
/// security, the loading bar, Copy Link, and Reload or Stop with the reload options.
struct PageAddressField: View {
    /// The page the field shows and drives.
    let webPage: WebPage?
    /// What a click on the address does, where the address can be edited.
    var onEdit: (() -> Void)? = nil

    @Environment(EngineRegistry.self) private var engineRegistry

    @State private var isHovered = false

    private var url: URL? {
        webPage?.url
    }

    private var isLoading: Bool {
        webPage?.isLoading == true
    }

    var body: some View {
        HStack(spacing: 0) {
            PageBackButton(webPage: webPage, canGoBack: webPage?.canGoBack == true)
            PageForwardButton(webPage: webPage, canGoForward: webPage?.canGoForward == true)
            domain
                .frame(maxWidth: .infinity)
            if url != nil {
                CopyLinkButton(copyURL: copyURL, copyMarkdown: copyMarkdown)
                    .opacity(isHovered ? 1 : 0)
                reloadButton
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .frame(height: Constants.PageControls.height)
        .overlay(alignment: .bottom) {
            LoadingIndicatorBar(isLoading: isLoading, progress: webPage?.estimatedProgress ?? 0, horizontalInset: Layout.loadingInset)
        }
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.2), value: webPage?.canGoForward == true)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("page-address-field")
        .task {
            await PublicSuffixList.shared.loadIfNeeded()
        }
    }

    // MARK: - Domain

    @ViewBuilder
    private var domain: some View {
        if let onEdit {
            Button(action: onEdit) {
                domainLabel
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Address")
            .accessibilityValue(url?.safeDisplayDomain ?? "")
            .help("Edit address")
        } else {
            domainLabel
        }
    }

    private var domainLabel: some View {
        HStack(spacing: 0) {
            if let engineID = webPage?.activeEngineID, engineID != .systemWebKit,
               let icon = engineRegistry.icon(for: engineID) {
                let descriptor = engineRegistry.descriptor(for: engineID)
                PageEngineBadge(
                    icon: icon,
                    engineName: descriptor.map { "\($0.displayName) (\($0.engineVersion))" } ?? engineID.rawValue,
                )
            }
            Text(url?.safeDisplayDomain ?? "")
                .font(.system(size: Constants.Typography.bodyMediumSize))
                .foregroundStyle(domainColor)
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    /// Red for an invalid certificate or mixed content, orange for a local network address,
    /// and secondary otherwise, including while the certificate is not yet evaluated.
    private var domainColor: Color {
        guard let certificate = webPage?.certificateInfo, let webPage else { return .secondary }
        switch webPage.securityState {
        case .secure:
            return .secondary
        case .mixedContent:
            return .red
        case .insecure:
            if case .invalid = certificate.trustState {
                return .red
            }
            return .secondary
        case .localNetwork:
            return .orange
        }
    }

    // MARK: - Reload

    private var reloadButton: some View {
        Button {
            if isLoading {
                webPage?.stopLoading()
            } else {
                _ = webPage?.reload()
            }
        } label: {
            Image(systemName: isLoading ? "xmark" : "arrow.clockwise")
                .font(.system(size: Constants.PageControls.buttonFontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Constants.PageControls.buttonWidth, height: Constants.PageControls.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isLoading ? "Stop" : "Reload")
        .accessibilityLabel(isLoading ? "Stop loading" : "Reload page")
        .modifier(ReloadOptionsMenu(
            onReload: { _ = webPage?.reload() },
            onReloadFromOrigin: { _ = webPage?.reload(fromOrigin: true) },
            onReloadWithoutContentBlockers: { webPage?.reloadWithoutContentBlockers() },
            otherEngines: engineRegistry.descriptors.filter { $0.id != (webPage?.activeEngineID ?? .systemWebKit) },
            onReloadInEngine: { engine in webPage?.reload(in: engine, registry: engineRegistry) },
        ))
    }

    // MARK: - Copy

    private func copyURL() {
        guard let url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.removingTrackingParameters().absoluteString, forType: .string)
    }

    private func copyMarkdown() {
        guard let url else { return }
        let cleanURL = url.removingTrackingParameters()
        let title = webPage?.title ?? cleanURL.host ?? "Link"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("[\(title)](\(cleanURL.absoluteString))", forType: .string)
    }

    private enum Layout {
        static let horizontalPadding: CGFloat = 6
        static let loadingInset: CGFloat = 8
    }
}
