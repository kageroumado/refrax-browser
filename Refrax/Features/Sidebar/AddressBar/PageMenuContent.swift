import Security
import SecurityInterface
import SwiftUI
import WebKit

/// Represents an extension that can appear in the page menu.
struct PageMenuExtension: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    let isEnabled: Bool
}

/// Popover content showing page information and actions.
///
/// Displays:
/// - Zoom controls
/// - Quick actions (copy URL, share, screenshot)
/// - Page tools (record, find, reader mode)
/// - Extensions
/// - Security & settings
struct PageMenuContent: View {
    let certificateInfo: CertificateInfo?
    let serverTrust: SecTrust?
    let currentZoom: Int
    let extensions: [PageMenuExtension]
    let isReaderAvailable: Bool
    let isReaderActive: Bool
    let isRecording: Bool
    let recordingStartTime: Date?
    let onZoomChanged: (Int) -> Void
    let onCopyURL: () -> Void
    let onShare: () -> Void
    let onScreenshotFullPage: () -> Void
    let onScreenshotVisibleArea: () -> Void
    let onScreenshotSelection: () -> Void
    let onScreenshotWindow: () -> Void
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onFindOnPage: () -> Void
    let onReaderMode: () -> Void
    let onWebpageSettings: () -> Void
    let onShowCookies: () -> Void
    let onExtensionAction: (String) -> Void

    private enum Layout {
        static let width: CGFloat = 280
        static let popoverPadding: CGFloat = 8
        static let groupSpacing: CGFloat = 6
        static let groupCornerRadius: CGFloat = 10
        static let itemCornerRadius: CGFloat = 6
        static let itemPadding: CGFloat = 8
        static let itemSpacing: CGFloat = 2
        static let iconSize: CGFloat = 16
        static let fontSize: CGFloat = 13
    }

    var body: some View {
        VStack(spacing: Layout.groupSpacing) {
            zoomSection
            quickActionsSection
            pageToolsSection

            if !extensions.isEmpty {
                extensionsSection
            }

            settingsSection
        }
        .padding(Layout.popoverPadding)
        .frame(width: Layout.width)
    }

    // MARK: - Sections

    private var zoomSection: some View {
        PageMenuSection {
            HStack {
                Label("Zoom", systemImage: "plus.magnifyingglass")
                    .font(.system(size: Layout.fontSize))
                    .labelStyle(.titleOnly)

                Spacer()

                Picker("", selection: Binding(
                    get: { currentZoom },
                    set: { onZoomChanged($0) },
                )) {
                    ForEach(Constants.AddressBar.zoomLevels, id: \.self) { value in
                        Text("\(value)%").tag(value)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, Layout.itemPadding)
            .padding(.vertical, 6)
        }
    }

    private var quickActionsSection: some View {
        PageMenuSection {
            VStack(spacing: Layout.itemSpacing) {
                PageMenuItem(title: "Copy URL", icon: "link", action: onCopyURL)
                PageMenuItem(title: "Share...", icon: "square.and.arrow.up", action: onShare)
            }

            screenshotRow
        }
    }

    private var screenshotRow: some View {
        HStack(spacing: 6) {
            ScreenshotButton(
                title: "Full Page",
                icon: "doc.richtext",
                action: onScreenshotFullPage,
            )

            ScreenshotButton(
                title: "Visible",
                icon: "rectangle.dashed",
                action: onScreenshotVisibleArea,
            )

            ScreenshotButton(
                title: "Selection",
                icon: "cursorarrow.and.square.on.square.dashed",
                action: onScreenshotSelection,
            )

            ScreenshotButton(
                title: "Window",
                icon: "macwindow",
                action: onScreenshotWindow,
            )
        }
        .padding(.horizontal, Layout.itemPadding)
        .padding(.vertical, 6)
    }

    private var pageToolsSection: some View {
        PageMenuSection {
            VStack(spacing: Layout.itemSpacing) {
                RecordingButton(
                    isRecording: isRecording,
                    recordingStartTime: recordingStartTime,
                    onStart: onStartRecording,
                    onStop: onStopRecording,
                )

                PageMenuItem(
                    title: "Find on Page...",
                    icon: "doc.text.magnifyingglass",
                    action: onFindOnPage,
                )

                if isReaderAvailable {
                    PageMenuItem(
                        title: isReaderActive ? "Exit Reader Mode" : "Enter Reader Mode",
                        icon: isReaderActive ? "doc.richtext.fill" : "doc.richtext",
                        action: onReaderMode,
                    )
                }
            }
        }
    }

    private var extensionsSection: some View {
        PageMenuSection {
            VStack(spacing: Layout.itemSpacing) {
                ForEach(extensions) { ext in
                    ExtensionMenuItem(
                        name: ext.name,
                        icon: ext.icon,
                        isEnabled: ext.isEnabled,
                    ) {
                        onExtensionAction(ext.id)
                    }
                }
            }
        }
    }

    private var settingsSection: some View {
        PageMenuSection {
            VStack(spacing: Layout.itemSpacing) {
                if serverTrust != nil {
                    PageMenuItem(
                        title: certificateTitle,
                        icon: certificateIcon,
                        iconColor: certificateColor,
                        action: showCertificatePanel,
                    )
                }

                PageMenuItem(
                    title: "Website Settings...",
                    icon: "gearshape",
                    action: onWebpageSettings,
                )
                PageMenuItem(title: "Cookies...", icon: "archivebox", action: onShowCookies)
            }
        }
    }

    // MARK: - Certificate Properties

    private var certificateTitle: String {
        guard let cert = certificateInfo else { return "Certificate" }
        switch cert.trustState {
        case .valid:
            return "Connection is Secure"
        case .invalid:
            return "Certificate Issue"
        case .unknown:
            return "View Certificate"
        }
    }

    private var certificateIcon: String {
        guard let cert = certificateInfo else { return "lock.fill" }
        switch cert.trustState {
        case .valid:
            return "lock.fill"
        case .invalid:
            return "lock.trianglebadge.exclamationmark.fill"
        case .unknown:
            return "lock.open.fill"
        }
    }

    private var certificateColor: Color? {
        guard let cert = certificateInfo else { return nil }
        switch cert.trustState {
        case .valid:
            return nil
        case .invalid:
            return .orange
        case .unknown:
            return nil
        }
    }

    // MARK: - Actions

    /// Shows the system certificate panel with full certificate details.
    ///
    /// Uses `SFCertificatePanel` which displays the certificate chain with
    /// detailed information (like Chrome's certificate viewer).
    private func showCertificatePanel() {
        guard let trust = serverTrust else { return }

        let panel = SFCertificatePanel.shared()
        panel?.runModal(for: trust, showGroup: true)
    }
}

// MARK: - Section Container

/// A visual grouping container for menu sections.
///
/// Provides consistent spacing and acts as a semantic container.
/// No background - the popover provides its own.
private struct PageMenuSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
    }
}

// MARK: - Screenshot Button

private struct ScreenshotButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    private enum Layout {
        static let cornerRadius: CGFloat = 6
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .frame(height: 20)

                Text(title)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .foregroundStyle(isHovered ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Layout.cornerRadius)
                    .fill(isHovered ? Color.appAccentColor.opacity(0.1) : Color.clear),
            )
            .contentShape(RoundedRectangle(cornerRadius: Layout.cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Extension Menu Item

private struct ExtensionMenuItem: View {
    let name: String
    let icon: NSImage?
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    private enum Layout {
        static let cornerRadius: CGFloat = 6
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 6
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                extensionIcon
                    .frame(width: 20, height: 20)

                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(isEnabled ? .primary : .secondary)

                Spacer()

                if !isEnabled {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, Layout.verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cornerRadius)
                    .fill(isHovered ? Color.appAccentColor.opacity(0.1) : Color.clear),
            )
            .contentShape(RoundedRectangle(cornerRadius: Layout.cornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var extensionIcon: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Recording Button

/// Button for starting/stopping tab video recording.
///
/// Shows a single button that changes state based on whether recording is active.
/// When recording, shows a pulsing indicator with elapsed time.
private struct RecordingButton: View {
    let isRecording: Bool
    let recordingStartTime: Date?
    let onStart: () -> Void
    let onStop: () -> Void

    @State private var isHovered = false

    private enum Layout {
        static let cornerRadius: CGFloat = 6
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 6
    }

    var body: some View {
        Button(action: isRecording ? onStop : onStart) {
            HStack(spacing: 8) {
                if isRecording {
                    RecordingIndicatorCompact()
                    Text("Stop Recording")
                        .font(.system(size: 13))
                    Spacer()
                    recordingDuration
                } else {
                    Image(systemName: "video")
                        .font(.system(size: 13))
                        .frame(width: 20)
                    Text("Record Tab")
                        .font(.system(size: 13))
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, Layout.verticalPadding)
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: Layout.cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var buttonBackground: some View {
        Group {
            if isRecording {
                Color.red.opacity(isHovered ? 0.2 : 0.1)
            } else if isHovered {
                Color.appAccentColor.opacity(0.1)
            } else {
                Color.clear
            }
        }
    }

    private var recordingDuration: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(formattedDuration(at: context.date))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.red)
        }
    }

    private func formattedDuration(at currentDate: Date) -> String {
        guard let startTime = recordingStartTime else { return "0:00" }
        let elapsed = currentDate.timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
