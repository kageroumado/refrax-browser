import AppKit
import SwiftUI

// MARK: - Detail Tray Container View

/// Container view for the detail tray that handles cursor tracking.
///
/// This view:
/// 1. Resets the cursor to arrow when mouse is over the tray (WebKit modifies cursor via `.set()`)
/// 2. Passes clicks through to subviews (glass view content) or views underneath
/// 3. Notifies the window controller when cursor enters/exits to block WebKit mouse events
///
/// Subviews receive clicks normally, and unclaimed clicks pass through to sibling views.
final class DetailTrayContainerView: NSView {
    private var trackingArea: NSTrackingArea?

    /// Called when the cursor enters or exits the tray container.
    /// The callback receives `true` when cursor enters, `false` when it exits.
    var onCursorPresenceChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    /// Remove tracking area before dealloc to prevent AppKit from
    /// delivering mouse events to a partially-deallocated view.
    /// The @objc thunk's Swift concurrency executor check can crash
    /// if the view is in dealloc when an event arrives.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil, let existing = trackingArea {
            removeTrackingArea(existing)
            trackingArea = nil
            onCursorPresenceChanged = nil
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil,
        )

        if let trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with _: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseEntered(with _: NSEvent) {
        NSCursor.arrow.set()
        onCursorPresenceChanged?(true)
    }

    override func mouseMoved(with _: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseExited(with _: NSEvent) {
        onCursorPresenceChanged?(false)
    }
}

// MARK: - Detail Tray Container

/// AppKit-level setup and animation for the detail tray panel.
///
/// The detail tray is a glass panel that slides in from the window's leading edge,
/// providing quick access to downloads, bookmarks, history, back/forward lists,
/// tab snapshots, and the Lightboard.
///
/// Uses Core Animation layer transforms for smooth 60fps animations.
extension RefraxWindowController {
    /// Whether the detail tray is currently visible.
    var isDetailTrayVisible: Bool {
        guard let container = detailTrayContainer else { return false }
        return !container.isHidden
    }

    // MARK: - Setup

    /// Sets up the AppKit-animated detail tray container.
    func setupDetailTrayContainer(contentView: NSView) {
        let padding = Constants.DetailTray.glassEffectPadding
        let trayWidth = Constants.DetailTray.width + padding * 2

        // Container handles cursor and notifies when cursor enters/exits
        let container = DetailTrayContainerView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Track cursor presence to conditionally block WebKit mouse events
        container.onCursorPresenceChanged = { [weak self] isInside in
            guard let self else { return }
            isCursorInDetailTray = isInside
            updateOverlayEventBlocking()
        }

        // Try to use private glass effect class for better appearance
        let glassView: NSGlassEffectView
        if let glassViewClass = NSClassFromString("NSContainerConcentricGlassEffectView") as? NSGlassEffectView.Type {
            glassView = glassViewClass.init()
            glassView.setValue(20.0, forKey: "concentricMinimumCornerRadius")
        } else {
            glassView = NSGlassEffectView()
        }

        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.cornerRadius = Constants.DetailTray.glassCornerRadius

        let trayContent = DetailTrayContent()
            .refraxEnvironment(environment)

        let hostingView = NSHostingView(rootView: trayContent)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        glassView.contentView = hostingView
        container.addSubview(glassView)

        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            glassView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            glassView.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            glassView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
        ])

        contentView.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.detailTrayLeading),
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: trayWidth),
        ])

        container.isHidden = true

        // Force layer creation and set initial hidden transform
        container.wantsLayer = true
        if let layer = container.layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = CATransform3DMakeTranslation(-trayWidth, 0, 0)
            CATransaction.commit()
        }

        detailTrayContainer = container
        detailTrayGlassView = glassView
    }

    // MARK: - Observation

    /// Observes detail tray state changes.
    func observeDetailTrayState() {
        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            let modeChanges = Observations { self.windowState.detailTrayMode }

            for await mode in modeChanges {
                if mode != .hidden {
                    showDetailTray()
                } else {
                    hideDetailTray()
                }
            }
        }
        observationTasks.append(task)
    }

    // MARK: - Show/Hide

    /// Shows the detail tray with animation.
    func showDetailTray() {
        guard let container = detailTrayContainer,
              let layer = container.layer else { return }

        detailTrayHideTask?.cancel()
        detailTrayHideTask = nil

        // If already visible, skip animation - content updates automatically via SwiftUI
        if isDetailTrayVisible {
            return
        }

        container.isHidden = false
        window?.invalidateCursorRects(for: container)

        // Calculate how far off-screen the tray needs to go (its entire visible extent)
        let padding = Constants.DetailTray.glassEffectPadding
        let trayWidth = Constants.DetailTray.width + padding * 2
        let trayMaxX = Self.detailTrayLeading + trayWidth
        let hiddenTransform = CATransform3DMakeTranslation(-trayMaxX, 0, 0)
        let visibleTransform = CATransform3DIdentity

        // If current transform is identity, layout reset it - snap to hidden first
        var fromTransform = layer.presentation()?.transform ?? layer.transform
        if CATransform3DIsIdentity(fromTransform) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = hiddenTransform
            CATransaction.commit()
            fromTransform = hiddenTransform
        }

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = fromTransform
        animation.toValue = visibleTransform
        animation.duration = CFTimeInterval(Constants.DetailTray.showDuration)
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.isRemovedOnCompletion = true

        CATransaction.begin()
        layer.add(animation, forKey: "detailTrayAnimation")
        layer.transform = visibleTransform
        CATransaction.commit()

        // Update trailing edge for SwiftUI views
        updateDetailTrayTrailingEdge()
    }

    /// Hides the detail tray with animation.
    func hideDetailTray() {
        guard let container = detailTrayContainer,
              let layer = container.layer else { return }

        // Clear trailing edge for SwiftUI views
        windowState.detailTrayTrailingEdge = 0

        // Cursor is no longer in tray once it's hiding
        isCursorInDetailTray = false
        updateOverlayEventBlocking()

        // Calculate how far off-screen the tray needs to go (its entire visible extent)
        let padding = Constants.DetailTray.glassEffectPadding
        let trayWidth = Constants.DetailTray.width + padding * 2
        let trayMaxX = Self.detailTrayLeading + trayWidth
        let hiddenTransform = CATransform3DMakeTranslation(-trayMaxX, 0, 0)

        let currentTransform = layer.presentation()?.transform ?? layer.transform

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = currentTransform
        animation.toValue = hiddenTransform
        animation.duration = CFTimeInterval(Constants.DetailTray.hideDuration)
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        animation.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated {
                container.isHidden = true
            }
        }
        layer.add(animation, forKey: "detailTrayAnimation")
        layer.transform = hiddenTransform
        CATransaction.commit()
    }

    /// Hides the detail tray instantly without animation.
    func hideDetailTrayInstantly() {
        guard let container = detailTrayContainer,
              let layer = container.layer else { return }

        // Clear trailing edge for SwiftUI views
        windowState.detailTrayTrailingEdge = 0

        // Cursor is no longer in tray once it's hidden
        isCursorInDetailTray = false
        updateOverlayEventBlocking()

        // Calculate how far off-screen the tray needs to go
        let padding = Constants.DetailTray.glassEffectPadding
        let trayWidth = Constants.DetailTray.width + padding * 2
        let trayMaxX = Self.detailTrayLeading + trayWidth

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeTranslation(-trayMaxX, 0, 0)
        CATransaction.commit()
        container.isHidden = true
    }

    // MARK: - Positioning

    /// Leading offset of the tray container: its glass sits a small gap from the window edge.
    private static let detailTrayLeading = Constants.DetailTray.gapFromEdge - Constants.DetailTray.glassEffectPadding

    // MARK: - Trailing Edge Tracking

    /// Updates the trailing edge position exposed to SwiftUI.
    ///
    /// Called whenever the tray position changes. SwiftUI views like `LinkHoverPreviewView`
    /// use this value to avoid overlapping with the tray.
    private func updateDetailTrayTrailingEdge() {
        guard isDetailTrayVisible else {
            windowState.detailTrayTrailingEdge = 0
            return
        }

        let padding = Constants.DetailTray.glassEffectPadding
        let trayWidth = Constants.DetailTray.width + padding * 2
        windowState.detailTrayTrailingEdge = Self.detailTrayLeading + trayWidth
    }

    // MARK: - Mouse Event Blocking

    /// Updates WebKit mouse event blocking based on cursor location.
    ///
    /// Events are blocked only while the cursor is inside the detail tray, so the page
    /// stays interactive while the tray is open.
    func updateOverlayEventBlocking() {
        if windowState.webViewsShouldIgnoreAllEvents != isCursorInDetailTray {
            windowState.webViewsShouldIgnoreAllEvents = isCursorInDetailTray
        }
    }
}
