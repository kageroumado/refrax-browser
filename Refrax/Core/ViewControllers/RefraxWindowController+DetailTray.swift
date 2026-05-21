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
/// Unlike the sidebar overlay which is an invisible tracking area, this container has
/// interactive SwiftUI content. Subviews receive clicks normally, and unclaimed clicks
/// pass through to sibling views (like the sidebar).
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
/// The detail tray is a secondary slide-out panel that appears adjacent to the sidebar,
/// providing quick access to downloads, bookmarks, and history. It uses the same
/// Liquid Glass styling as the sidebar overlay.
///
/// ## Positioning States
///
/// The tray positions itself based on sidebar state:
/// 1. **Sidebar expanded**: Adjacent to sidebar trailing edge with gap
/// 2. **Sidebar collapsed + overlay visible**: Adjacent to overlay trailing edge
/// 3. **Sidebar collapsed + overlay hidden**: Floats at left edge with glass effect
///
/// ## Animation
///
/// Uses Core Animation layer transforms for smooth 60fps animations,
/// matching the sidebar overlay implementation.
///
/// ## Z-Order Limitation
///
/// The detail tray renders above the split view (including the sidebar) due to subview order.
/// Ideally the tray would render beneath the sidebar so it appears to slide out from under it.
/// However, the sidebar is nested inside `NSSplitView` which renders as a single unit—we cannot
/// interleave the tray between the sidebar and content areas. Layer `zPosition` only affects
/// sibling ordering, not cross-subtree rendering. Clipping masks don't work well because the
/// sidebar uses semi-transparent Liquid Glass materials. This is accepted as a visual limitation.
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

        // Position constraint - will be updated dynamically based on sidebar state
        let leadingConstraint = container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)

        NSLayoutConstraint.activate([
            leadingConstraint,
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
        detailTrayLeadingConstraint = leadingConstraint
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
              let layer = container.layer,
              let leadingConstraint = detailTrayLeadingConstraint else { return }

        detailTrayHideTask?.cancel()
        detailTrayHideTask = nil

        // If already visible, skip animation - content updates automatically via SwiftUI
        if isDetailTrayVisible {
            return
        }

        // Update position based on current sidebar state
        updateDetailTrayPosition(animated: false)

        container.isHidden = false
        window?.invalidateCursorRects(for: container)

        // Calculate how far off-screen the tray needs to go (its entire visible extent)
        let padding = Constants.DetailTray.glassEffectPadding
        let trayWidth = Constants.DetailTray.width + padding * 2
        let trayMaxX = leadingConstraint.constant + trayWidth
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
              let layer = container.layer,
              let leadingConstraint = detailTrayLeadingConstraint else { return }

        // Clear trailing edge for SwiftUI views
        windowState.detailTrayTrailingEdge = 0

        // Cursor is no longer in tray once it's hiding
        isCursorInDetailTray = false
        updateOverlayEventBlocking()

        // Calculate how far off-screen the tray needs to go (its entire visible extent)
        let padding = Constants.DetailTray.glassEffectPadding
        let trayWidth = Constants.DetailTray.width + padding * 2
        let trayMaxX = leadingConstraint.constant + trayWidth
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
              let layer = container.layer,
              let leadingConstraint = detailTrayLeadingConstraint else { return }

        // Clear trailing edge for SwiftUI views
        windowState.detailTrayTrailingEdge = 0

        // Cursor is no longer in tray once it's hidden
        isCursorInDetailTray = false
        updateOverlayEventBlocking()

        // Calculate how far off-screen the tray needs to go
        let padding = Constants.DetailTray.glassEffectPadding
        let trayWidth = Constants.DetailTray.width + padding * 2
        let trayMaxX = leadingConstraint.constant + trayWidth

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeTranslation(-trayMaxX, 0, 0)
        CATransaction.commit()
        container.isHidden = true
    }

    // MARK: - Positioning

    /// Calculates the detail tray leading offset for a given overlay progress.
    ///
    /// The tray glass should be positioned with an 8px gap from either:
    /// - The window edge (when overlay is hidden)
    /// - The overlay glass trailing edge (when overlay is visible)
    ///
    /// - Parameter overlayProgress: The overlay animation progress (0 = hidden, 1 = fully visible)
    /// - Returns: The leading constraint constant for the tray
    private func detailTrayLeadingOffset(forOverlayProgress overlayProgress: CGFloat) -> CGFloat {
        let trayGlassPadding = Constants.DetailTray.glassEffectPadding
        let overlayGlassPadding = Constants.SidebarAnimation.glassEffectPadding
        let gap = Constants.DetailTray.gapFromOverlay

        // Overlay glass trailing edge position (sidebar width + one padding on the left)
        // The overlay container starts at x=0, glass is inset by padding, so trailing is:
        // 0 + overlayGlassPadding + sidebarThickness = sidebarThickness + overlayGlassPadding
        let overlayGlassTrailing = windowState.sidebarThickness + overlayGlassPadding

        // Tray glass leading when adjacent to overlay:
        // overlayGlassTrailing + gap = sidebarThickness + overlayGlassPadding + gap
        // Tray container leading = tray glass leading - tray padding
        let overlayPosition = overlayGlassTrailing + gap - trayGlassPadding

        // Tray glass leading when at edge: gap (8px from window edge)
        // Tray container leading = gap - tray padding
        let edgePosition = gap - trayGlassPadding

        // Interpolate based on progress
        return edgePosition + (overlayPosition - edgePosition) * overlayProgress
    }

    /// Detail tray leading offset when in compact sidebar mode.
    ///
    /// All inputs are constants so this is computed once. In compact mode, the
    /// overlay is `compactWidth + padding` instead of the full `sidebarThickness`,
    /// so the tray positions adjacent to the narrower compact strip.
    private static let compactDetailTrayLeading: CGFloat = {
        let trayGlassPadding = Constants.DetailTray.glassEffectPadding
        let overlayGlassPadding = Constants.SidebarAnimation.glassEffectPadding
        let gap = Constants.DetailTray.gapFromOverlay
        let compactGlassTrailing = Constants.SidebarAnimation.compactWidth + overlayGlassPadding
        return compactGlassTrailing + gap - trayGlassPadding
    }()

    /// Calculates the target leading constraint value based on sidebar state.
    private func calculateDetailTrayLeading() -> CGFloat {
        let sidebarItem = splitViewController.splitViewItems[0]

        if !sidebarItem.isCollapsed {
            // Sidebar expanded: position adjacent to sidebar with 16px gap
            let glassPadding = Constants.DetailTray.glassEffectPadding
            let expandedGap = Constants.DetailTray.gapFromExpandedSidebar
            let sidebarFrame = sidebarItem.viewController.view.frame
            let sidebarTrailing = sidebarFrame.origin.x + sidebarFrame.width
            return sidebarTrailing + expandedGap - glassPadding
        } else if windowState.effectiveSidebarMode == .compact, isSidebarOverlayVisible {
            // Compact mode with overlay visible: position adjacent to compact strip
            return Self.compactDetailTrayLeading
        } else if isSidebarOverlayVisible {
            // Sidebar collapsed, overlay visible: position adjacent to overlay
            return detailTrayLeadingOffset(forOverlayProgress: 1.0)
        } else {
            // Sidebar collapsed, overlay hidden: float at left edge
            return detailTrayLeadingOffset(forOverlayProgress: 0.0)
        }
    }

    /// Updates the detail tray position based on sidebar state.
    ///
    /// - Parameter animated: Whether to animate the position change.
    func updateDetailTrayPosition(animated: Bool) {
        guard let leadingConstraint = detailTrayLeadingConstraint else { return }

        leadingConstraint.constant = calculateDetailTrayLeading()

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Constants.DetailTray.repositionDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true

                detailTrayContainer?.superview?.layoutSubtreeIfNeeded()
            }
        } else {
            detailTrayContainer?.superview?.layoutSubtreeIfNeeded()
        }

        updateDetailTrayTrailingEdge()
    }

    /// Updates the detail tray position to follow the sidebar overlay progress.
    ///
    /// Called during cursor-tracking phase to keep the tray synchronized with
    /// the overlay as it follows the cursor.
    ///
    /// - Parameter progress: Overlay progress (0 = hidden, 1 = fully visible)
    func updateDetailTrayForOverlayProgress(_ progress: CGFloat) {
        guard isDetailTrayVisible, let leadingConstraint = detailTrayLeadingConstraint else { return }

        leadingConstraint.constant = detailTrayLeadingOffset(forOverlayProgress: progress)
        updateDetailTrayTrailingEdge()
    }

    /// Animates the detail tray position with the given parameters.
    ///
    /// Used to synchronize tray animation with overlay snap/hide animations.
    ///
    /// - Parameters:
    ///   - overlayProgress: Target overlay progress (0 = hidden, 1 = fully visible)
    ///   - duration: Animation duration
    func animateDetailTrayToOverlayProgress(_ overlayProgress: CGFloat, duration: CGFloat) {
        guard isDetailTrayVisible, let leadingConstraint = detailTrayLeadingConstraint else { return }

        let targetLeading = detailTrayLeadingOffset(forOverlayProgress: overlayProgress)

        leadingConstraint.constant = targetLeading

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            detailTrayContainer?.superview?.layoutSubtreeIfNeeded()
        }

        updateDetailTrayTrailingEdge()
    }

    /// Instantly updates the detail tray position without animation.
    ///
    /// Used when overlay hides instantly (e.g., sidebar expands).
    ///
    /// - Parameter overlayProgress: Target overlay progress
    func setDetailTrayToOverlayProgressInstantly(_ overlayProgress: CGFloat) {
        guard isDetailTrayVisible, let leadingConstraint = detailTrayLeadingConstraint else { return }

        leadingConstraint.constant = detailTrayLeadingOffset(forOverlayProgress: overlayProgress)
        detailTrayContainer?.superview?.layoutSubtreeIfNeeded()
        updateDetailTrayTrailingEdge()
    }

    // MARK: - Trailing Edge Tracking

    /// Updates the trailing edge position exposed to SwiftUI.
    ///
    /// Called whenever the tray position changes. SwiftUI views like `LinkHoverPreviewView`
    /// use this value to avoid overlapping with the tray.
    private func updateDetailTrayTrailingEdge() {
        guard isDetailTrayVisible, let leadingConstraint = detailTrayLeadingConstraint else {
            windowState.detailTrayTrailingEdge = 0
            return
        }

        let padding = Constants.DetailTray.glassEffectPadding
        let trayWidth = Constants.DetailTray.width + padding * 2
        windowState.detailTrayTrailingEdge = leadingConstraint.constant + trayWidth
    }

    // MARK: - Mouse Event Blocking

    /// Updates WebKit mouse event blocking based on cursor location.
    ///
    /// Events should only be blocked when the cursor is inside the sidebar overlay
    /// or detail tray, not when it's over the web content. This allows normal web interaction
    /// while the overlays are visible.
    func updateOverlayEventBlocking() {
        let isCursorInOverlay = isCursorInSidebarOverlay || isCursorInDetailTray
        if windowState.webViewsShouldIgnoreAllEvents != isCursorInOverlay {
            windowState.webViewsShouldIgnoreAllEvents = isCursorInOverlay
        }
    }
}
