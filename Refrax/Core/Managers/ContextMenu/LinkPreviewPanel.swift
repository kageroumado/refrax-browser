import AppKit
import SwiftUI
import WebKit

/// A floating panel for previewing links.
///
/// This panel displays a web page preview with a minimal toolbar showing the page title.
/// It animates from the link's position (reveal animation) and can be closed by clicking
/// the close button or pressing Escape.
///
/// ## Animation
///
/// The panel uses a mask-based reveal animation that expands from the origin rect
/// (typically the link's position) to the full panel size. The disappearance animation
/// reverses this effect.
///
/// ## Usage
///
/// Created and managed by `LinkPreviewManager` in response to Shift+Click on links.
final class LinkPreviewPanel: NSPanel, NSWindowDelegate {
    // MARK: - Animation Constants

    private enum Animation {
        static let appearDuration: CFTimeInterval = 0.35
        static let disappearDuration: CFTimeInterval = 0.25
        static let easeOutExpo = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        static let easeInExpo = CAMediaTimingFunction(controlPoints: 0.7, 0, 0.84, 0)
    }

    // MARK: - Properties

    private let onClose: () -> Void
    private let onOpenInNewTab: () -> Void
    private let onShare: (NSView) -> Void
    private var isClosing = false

    /// The rect where the animation originates from (link position in screen coordinates).
    private let originRect: NSRect

    /// The final frame of the panel.
    private let finalFrame: NSRect

    /// The mask layer used for the reveal animation.
    private var maskLayer: CAShapeLayer?

    /// The container view that holds the content and applies the mask.
    private var containerView: NSView?

    // MARK: - Initialization

    init(
        webPage: WebPage,
        size: NSSize,
        originRect: NSRect,
        finalFrame: NSRect,
        onClose: @escaping () -> Void,
        onOpenInNewTab: @escaping () -> Void,
        onShare: @escaping (NSView) -> Void,
    ) {
        self.onClose = onClose
        self.onOpenInNewTab = onOpenInNewTab
        self.onShare = onShare
        self.originRect = originRect
        self.finalFrame = finalFrame

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )

        delegate = self
        level = .normal
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false

        setupContent(webPage: webPage, size: size)
    }

    // MARK: - Setup

    private func setupContent(webPage: WebPage, size: NSSize) {
        let contentView = LinkPreviewPanelView(
            webPage: webPage,
            onClose: { [weak self] in self?.closePanel() },
            onOpenInNewTab: { [weak self] in self?.onOpenInNewTab() },
            onShare: { [weak self] button in self?.onShare(button) },
        )

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(origin: .zero, size: size)

        // Create a container view for masking
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.addSubview(hostingView)

        self.contentView = container
        containerView = container
    }

    // MARK: - Animation

    /// Animates the panel appearance from the origin rect to full size.
    func animateAppearance() {
        guard let containerView, let layer = containerView.layer else { return }

        // Calculate the origin rect relative to the panel's coordinate system
        let originInPanel = convertOriginToPanel()

        // Create the mask layer
        let mask = CAShapeLayer()
        mask.frame = layer.bounds

        // Start with a rounded rect at the origin position
        let startPath = CGPath(
            roundedRect: originInPanel,
            cornerWidth: 10,
            cornerHeight: 10,
            transform: nil,
        )

        // End with the full panel bounds
        let endPath = CGPath(
            roundedRect: layer.bounds,
            cornerWidth: 20,
            cornerHeight: 20,
            transform: nil,
        )

        mask.path = startPath
        layer.mask = mask
        maskLayer = mask

        // Animate the mask path
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = startPath
        animation.toValue = endPath
        animation.duration = Animation.appearDuration
        animation.timingFunction = Animation.easeOutExpo
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false

        // Also animate opacity for a subtle fade-in effect
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 0.8
        opacityAnimation.toValue = 1.0
        opacityAnimation.duration = Animation.appearDuration * 0.5
        opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            // Remove the mask after animation completes
            self?.containerView?.layer?.mask = nil
            self?.maskLayer = nil
        }

        mask.add(animation, forKey: "revealAnimation")
        layer.add(opacityAnimation, forKey: "fadeIn")

        CATransaction.commit()
    }

    /// Animates the panel disappearance, shrinking back toward the origin.
    ///
    /// - Parameter completion: Called when the animation completes.
    func animateDisappearance(completion: @escaping () -> Void) {
        guard let containerView, let layer = containerView.layer else {
            completion()
            return
        }

        // Calculate the origin rect relative to the panel's coordinate system
        let originInPanel = convertOriginToPanel()

        // Create the mask layer
        let mask = CAShapeLayer()
        mask.frame = layer.bounds

        // Start with full panel bounds
        let startPath = CGPath(
            roundedRect: layer.bounds,
            cornerWidth: 20,
            cornerHeight: 20,
            transform: nil,
        )

        // End with a rounded rect at the origin position
        let endPath = CGPath(
            roundedRect: originInPanel,
            cornerWidth: 10,
            cornerHeight: 10,
            transform: nil,
        )

        mask.path = startPath
        layer.mask = mask
        maskLayer = mask

        // Animate the mask path (reverse of appearance)
        let pathAnimation = CABasicAnimation(keyPath: "path")
        pathAnimation.fromValue = startPath
        pathAnimation.toValue = endPath
        pathAnimation.duration = Animation.disappearDuration
        pathAnimation.timingFunction = Animation.easeInExpo
        pathAnimation.fillMode = .forwards
        pathAnimation.isRemovedOnCompletion = false

        // Also animate opacity for fade-out
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 1.0
        opacityAnimation.toValue = 0.0
        opacityAnimation.duration = Animation.disappearDuration
        opacityAnimation.timingFunction = Animation.easeInExpo
        opacityAnimation.fillMode = .forwards
        opacityAnimation.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            completion()
        }

        mask.add(pathAnimation, forKey: "hideAnimation")
        layer.add(opacityAnimation, forKey: "fadeOut")

        CATransaction.commit()
    }

    /// Converts the origin rect from screen coordinates to panel-relative coordinates.
    private func convertOriginToPanel() -> CGRect {
        // The origin rect is in screen coordinates
        // We need to convert it to the panel's content view coordinates

        // Get the origin rect center in screen coordinates
        let originCenter = NSPoint(
            x: originRect.midX,
            y: originRect.midY,
        )

        // Convert to panel window coordinates
        let panelOrigin = frame.origin
        let relativeCenter = NSPoint(
            x: originCenter.x - panelOrigin.x,
            y: originCenter.y - panelOrigin.y,
        )

        // Create a rect centered at the relative position with the original size
        // But clamp it to be within the panel bounds
        let width = min(originRect.width, frame.width * 0.3)
        let height = min(originRect.height, frame.height * 0.3)

        let x = max(0, min(relativeCenter.x - width / 2, frame.width - width))
        let y = max(0, min(relativeCenter.y - height / 2, frame.height - height))

        return CGRect(x: x, y: y, width: max(width, 100), height: max(height, 50))
    }

    // MARK: - Actions

    private func closePanel() {
        guard !isClosing else { return }
        isClosing = true

        // Animate the disappearance, then close
        animateDisappearance { [weak self] in
            self?.close()
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_: Notification) {
        if !isClosing {
            isClosing = true
        }
        onClose()
    }

    // MARK: - Key Handling

    override func keyDown(with event: NSEvent) {
        // Close on Escape
        if event.keyCode == 53 {
            closePanel()
            return
        }
        super.keyDown(with: event)
    }

    override var canBecomeKey: Bool {
        true
    }
}

// MARK: - Link Preview Panel View

/// SwiftUI view for the link preview panel content.
///
/// Layout:
/// - Outer container with 20pt corner radius and frosted glass background
/// - 40pt toolbar with close button (left), title (center), share and "Open in New Tab" (right)
/// - Web content inset 8pt from bottom/left/right with 12pt corner radius
private struct LinkPreviewPanelView: View {
    let webPage: WebPage
    let onClose: () -> Void
    let onOpenInNewTab: () -> Void
    let onShare: (NSView) -> Void

    private enum Layout {
        static let outerCornerRadius: CGFloat = 20
        static let innerCornerRadius: CGFloat = 12
        static let contentInset: CGFloat = 8
        static let toolbarHeight: CGFloat = 40
    }

    /// Dynamic title that observes WebPage changes.
    private var title: String {
        webPage.title.isEmpty ? (webPage.url?.host ?? "Preview") : webPage.title
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            webContent
        }
        .background {
            backgroundView
        }
        .clipShape(RoundedRectangle(cornerRadius: Layout.outerCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.outerCornerRadius)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            // Title
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            // Share button
            ShareButton(onShare: onShare)

            // Open in New Tab button
            Button(action: onOpenInNewTab) {
                Text("Open in New Tab")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: Layout.toolbarHeight)
    }

    // MARK: - Web Content

    private var webContent: some View {
        WebViewWrapper(webView: webPage.backingWebView)
            .clipShape(RoundedRectangle(cornerRadius: Layout.innerCornerRadius))
            .padding([.leading, .trailing, .bottom], Layout.contentInset)
    }

    // MARK: - Background

    private var backgroundView: some View {
        ZStack {
            // Backdrop blur
            BackdropBlurView(blurRadius: 30)

            // Semi-transparent tint
            Color(.windowBackgroundColor)
                .opacity(0.8)
        }
    }
}

// MARK: - Share Button

/// A share button that provides its NSView for the share picker.
private struct ShareButton: NSViewRepresentable {
    let onShare: (NSView) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")
        button.bezelStyle = .smallSquare
        button.isBordered = true
        button.target = context.coordinator
        button.action = #selector(Coordinator.buttonClicked(_:))
        // Constrain width to prevent excessive expansion
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.onShare = onShare
        button.target = context.coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onShare: onShare)
    }

    final class Coordinator {
        var onShare: (NSView) -> Void

        init(onShare: @escaping (NSView) -> Void) {
            self.onShare = onShare
        }

        @objc
        func buttonClicked(_ sender: NSButton) {
            onShare(sender)
        }
    }
}

// MARK: - WebView Wrapper

/// NSViewRepresentable wrapper for WKWebView.
private struct WebViewWrapper: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context _: Context) -> WKWebView {
        webView
    }

    func updateNSView(_: WKWebView, context _: Context) {
        // No updates needed
    }
}
