import AppKit
import WebKit

/// Result of a media capture permission dialog.
enum MediaCapturePermissionResult: Sendable {
    /// User granted permission for this session only.
    case allowOnce
    /// User granted permission and wants it saved for future visits.
    case alwaysAllow
    /// User denied the permission.
    case deny
}

/// Presents a custom media capture permission alert with Allow Once / Always Allow / Deny options.
///
/// This replaces WebKit's native permission dialog to provide:
/// - Clear distinction between one-time and persistent grants
/// - Consistent UI matching Safari's permission dialogs
/// - Vertical button layout for clear hierarchy
enum MediaCapturePermissionAlert {
    /// Presents a permission alert for media capture requests.
    ///
    /// The alert shows three options stacked vertically:
    /// - **Allow Once** — Grants for this session, not saved (prominent, blue)
    /// - **Always Allow** — Grants and saves to site settings
    /// - **Don't Allow** — Denies the request
    ///
    /// - Parameters:
    ///   - type: The type of media capture being requested.
    ///   - origin: The security origin (domain) requesting access.
    ///   - window: The window to attach the sheet to.
    /// - Returns: The user's permission decision.
    @MainActor
    static func present(
        for type: WKMediaCaptureType,
        origin: WKSecurityOrigin,
        in window: NSWindow,
    ) async -> MediaCapturePermissionResult {
        await withCheckedContinuation { continuation in
            let permissionName = permissionDisplayName(for: type)

            // Track whether we've already resumed to avoid double-resume
            var hasResumed = false
            let safeResume: (MediaCapturePermissionResult) -> Void = { result in
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: result)
            }

            // Create a panel for custom layout
            let panel = PermissionPanel(
                domain: origin.host,
                permissionName: permissionName,
                icon: systemIcon(for: type),
                onResult: safeResume,
            )

            window.beginSheet(panel) { response in
                // Fallback for escape key or programmatic close without button click
                if response == .cancel {
                    safeResume(.deny)
                }
            }
        }
    }

    /// Returns a human-readable name for the capture type.
    private static func permissionDisplayName(for type: WKMediaCaptureType) -> String {
        switch type {
        case .camera:
            "camera"
        case .microphone:
            "microphone"
        case .cameraAndMicrophone:
            "camera and microphone"
        @unknown default:
            "camera and microphone"
        }
    }

    /// Returns an appropriate system icon for the capture type.
    private static func systemIcon(for type: WKMediaCaptureType) -> NSImage? {
        let symbolName = switch type {
        case .camera:
            "video.fill"
        case .microphone:
            "mic.fill"
        case .cameraAndMicrophone:
            "video.badge.waveform.fill"
        @unknown default:
            "video.badge.waveform.fill"
        }

        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return nil
        }

        // Large icon with secondary label color (gray) like Safari
        let config = NSImage.SymbolConfiguration(pointSize: 56, weight: .medium)
            .applying(.init(paletteColors: [.secondaryLabelColor]))
        return image.withSymbolConfiguration(config)
    }
}

// MARK: - Permission Panel

/// Custom panel for permission dialogs matching Safari's style.
private final class PermissionPanel: NSPanel {
    private var hasResumed = false
    private let onResult: (MediaCapturePermissionResult) -> Void

    /// Calculates the height needed for wrapped text at a given width.
    private static func calculateWrappedTextHeight(text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let cell = NSTextFieldCell(textCell: text)
        cell.font = font
        cell.wraps = true
        cell.isScrollable = false
        cell.lineBreakMode = .byWordWrapping
        let bounds = NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
        return cell.cellSize(forBounds: bounds).height
    }

    /// Layout constants matching Safari's permission dialogs.
    private enum Layout {
        static let buttonWidth: CGFloat = 225
        static let buttonHeight: CGFloat = 28
        static let buttonCornerRadius: CGFloat = 14
        static let buttonSpacing: CGFloat = 8
        static let horizontalPadding: CGFloat = 16
        static let bottomPadding: CGFloat = 16
        static let topPadding: CGFloat = 20
        static let iconSize: CGFloat = 56
        static let iconToTitleSpacing: CGFloat = 12
        static let titleToSubtitleSpacing: CGFloat = 6
        static let subtitleToButtonsSpacing: CGFloat = 16
        static let panelWidth: CGFloat = 257

        /// Calculates total panel height based on dynamic title height.
        static func panelHeight(titleHeight: CGFloat, subtitleHeight: CGFloat) -> CGFloat {
            topPadding + iconSize + iconToTitleSpacing + titleHeight + titleToSubtitleSpacing
                + subtitleHeight + subtitleToButtonsSpacing + (3 * buttonHeight) + (2 * buttonSpacing)
                + bottomPadding
        }
    }

    init(
        domain: String,
        permissionName: String,
        icon: NSImage?,
        onResult: @escaping (MediaCapturePermissionResult) -> Void,
    ) {
        self.onResult = onResult

        // Create text fields first to measure their natural sizes
        let textWidth = Layout.buttonWidth
        let titleText = "\"\(domain)\" would like to access your \(permissionName)"
        let subtitleText = "You can change this later in Site Settings."

        // Calculate title height using cell's sizing for wrapped text
        let titleHeight = Self.calculateWrappedTextHeight(
            text: titleText,
            font: .systemFont(ofSize: 13, weight: .semibold),
            width: textWidth,
        )

        // Calculate subtitle height (single line)
        let subtitleHeight = Self.calculateWrappedTextHeight(
            text: subtitleText,
            font: .systemFont(ofSize: 12),
            width: textWidth,
        )

        let panelHeight = Layout.panelHeight(titleHeight: titleHeight, subtitleHeight: subtitleHeight)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Layout.panelWidth, height: panelHeight),
            styleMask: [.titled, .docModalWindow],
            backing: .buffered,
            defer: true,
        )

        setupContent(
            domain: domain,
            permissionName: permissionName,
            icon: icon,
            titleHeight: titleHeight,
            subtitleHeight: subtitleHeight,
            panelHeight: panelHeight,
        )
    }

    private func setupContent(
        domain: String,
        permissionName: String,
        icon: NSImage?,
        titleHeight: CGFloat,
        subtitleHeight: CGFloat,
        panelHeight: CGFloat,
    ) {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: Layout.panelWidth, height: panelHeight))

        // Gray background like Safari's permission popover
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let textWidth = Layout.buttonWidth
        var currentY = panelHeight - Layout.topPadding

        // Icon (centered)
        currentY -= Layout.iconSize
        let iconView = NSImageView(frame: NSRect(
            x: (Layout.panelWidth - Layout.iconSize) / 2,
            y: currentY,
            width: Layout.iconSize,
            height: Layout.iconSize,
        ))
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        contentView.addSubview(iconView)

        // Title (left-aligned, unlimited lines)
        currentY -= Layout.iconToTitleSpacing
        let title = NSTextField(labelWithString: "\"\(domain)\" would like to access your \(permissionName)")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.alignment = .left
        title.lineBreakMode = .byWordWrapping
        title.maximumNumberOfLines = 0
        title.cell?.wraps = true
        title.cell?.isScrollable = false
        currentY -= titleHeight
        title.frame = NSRect(x: Layout.horizontalPadding, y: currentY, width: textWidth, height: titleHeight)
        contentView.addSubview(title)

        // Subtitle (left-aligned, gray, wrapping)
        currentY -= Layout.titleToSubtitleSpacing
        let subtitle = NSTextField(labelWithString: "You can change this later in Site Settings.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .left
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 0
        subtitle.cell?.wraps = true
        subtitle.cell?.isScrollable = false
        currentY -= subtitleHeight
        subtitle.frame = NSRect(x: Layout.horizontalPadding, y: currentY, width: textWidth, height: subtitleHeight)
        contentView.addSubview(subtitle)

        // Buttons (stacked vertically, pill-shaped)
        currentY -= Layout.subtitleToButtonsSpacing

        // Allow Once (primary, blue filled)
        currentY -= Layout.buttonHeight
        let allowOnceButton = createPillButton(
            title: "Allow Once",
            isPrimary: true,
            action: #selector(allowOnce),
        )
        allowOnceButton.frame = NSRect(x: Layout.horizontalPadding, y: currentY, width: Layout.buttonWidth, height: Layout.buttonHeight)
        allowOnceButton.keyEquivalent = "\r"
        contentView.addSubview(allowOnceButton)

        // Always Allow (secondary, gray outline)
        currentY -= Layout.buttonSpacing + Layout.buttonHeight
        let alwaysAllowButton = createPillButton(
            title: "Always Allow",
            isPrimary: false,
            action: #selector(alwaysAllow),
        )
        alwaysAllowButton.frame = NSRect(x: Layout.horizontalPadding, y: currentY, width: Layout.buttonWidth, height: Layout.buttonHeight)
        contentView.addSubview(alwaysAllowButton)

        // Don't Allow (secondary, gray outline)
        currentY -= Layout.buttonSpacing + Layout.buttonHeight
        let denyButton = createPillButton(
            title: "Don't Allow",
            isPrimary: false,
            action: #selector(deny),
        )
        denyButton.frame = NSRect(x: Layout.horizontalPadding, y: currentY, width: Layout.buttonWidth, height: Layout.buttonHeight)
        denyButton.keyEquivalent = "\u{1b}"
        contentView.addSubview(denyButton)

        self.contentView = contentView
    }

    private func createPillButton(title: String, isPrimary: Bool, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = Layout.buttonCornerRadius

        if isPrimary {
            // Blue filled button with white text
            button.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            button.contentTintColor = .white
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                ],
            )
        } else {
            // Gray outlined button
            button.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .foregroundColor: NSColor.labelColor,
                    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                ],
            )
        }

        return button
    }

    @objc
    private func allowOnce() {
        guard !hasResumed else { return }
        hasResumed = true
        onResult(.allowOnce)
        sheetParent?.endSheet(self, returnCode: .OK)
    }

    @objc
    private func alwaysAllow() {
        guard !hasResumed else { return }
        hasResumed = true
        onResult(.alwaysAllow)
        sheetParent?.endSheet(self, returnCode: .OK)
    }

    @objc
    private func deny() {
        guard !hasResumed else { return }
        hasResumed = true
        onResult(.deny)
        sheetParent?.endSheet(self, returnCode: .cancel)
    }
}
