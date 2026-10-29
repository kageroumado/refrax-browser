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
/// The detail tray is a glass panel that slides in from the window edge on the control island's side,
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

        let hostingView = NSHostingView(rootView: LibraryDrawerSurface().refraxEnvironment(environment))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.sizingOptions = []
        // The title bar is hidden behind the islands; its safe area would push the drawer down
        // and past the window's bottom edge, out of line with the other islands.
        hostingView.safeAreaRegions = []
        container.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        contentView.addSubview(container)

        let leading = container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.defaultDetailTrayLeading)
        NSLayoutConstraint.activate([
            leading,
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
        detailTrayLeadingConstraint = leading
    }

    // MARK: - Observation

    /// Observes detail tray state changes.
    func observeDetailTrayState() {
        let task = Task(name: "Follow the library drawer") { [weak self] in
            guard let self else { return }

            let modeChanges = Observations {
                (self.windowState.detailTrayMode, self.windowState.controlIsland.railFrame, self.windowState.controlIsland.placement)
            }

            for await (mode, _, _) in modeChanges {
                updateDetailTrayPosition()
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
        registerDetailTrayDismissal()

        // If already visible, skip animation - content updates automatically via SwiftUI
        if isDetailTrayVisible {
            return
        }

        container.isHidden = false
        window?.invalidateCursorRects(for: container)

        let hiddenTransform = detailTrayHiddenTransform
        let visibleTransform = CATransform3DIdentity

        // Start past the edge on the tray's current side: the rail may have changed sides
        // since the tray last hid, and layout may have reset the transform.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = hiddenTransform
        CATransaction.commit()
        let fromTransform = hiddenTransform

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

        OutsideClickDismissal.shared.unregister(detailTrayDismissal)
        detailTrayDismissal = nil

        // Clear trailing edge for SwiftUI views
        windowState.detailTrayTrailingEdge = 0

        // Cursor is no longer in tray once it's hiding
        isCursorInDetailTray = false
        updateOverlayEventBlocking()

        let hiddenTransform = detailTrayHiddenTransform

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

        OutsideClickDismissal.shared.unregister(detailTrayDismissal)
        detailTrayDismissal = nil

        // Clear trailing edge for SwiftUI views
        windowState.detailTrayTrailingEdge = 0

        // Cursor is no longer in tray once it's hidden
        isCursorInDetailTray = false
        updateOverlayEventBlocking()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = detailTrayHiddenTransform
        CATransaction.commit()
        container.isHidden = true
    }

    /// A click outside the drawer's glass, or Esc, puts the drawer away; that click does nothing else.
    private func registerDetailTrayDismissal() {
        guard detailTrayDismissal == nil, let window else { return }
        detailTrayDismissal = OutsideClickDismissal.shared.register(in: window) { [weak self] in
            guard let container = self?.detailTrayContainer, !container.isHidden else { return nil }
            let padding = Constants.DetailTray.glassEffectPadding
            return container.convert(container.bounds, to: nil).insetBy(dx: padding, dy: padding)
        } dismiss: { [weak self] in
            self?.windowState.hideDetailTray()
        }
    }

    // MARK: - Positioning

    /// Leading offset of the tray container: its glass sits a small gap from the window edge.
    private static let defaultDetailTrayLeading = Constants.DetailTray.gapFromEdge - Constants.DetailTray.glassEffectPadding

    private var detailTrayLeading: CGFloat {
        detailTrayLeadingConstraint?.constant ?? Self.defaultDetailTrayLeading
    }

    /// The tray's container width: the glass and its padding on both sides.
    private var detailTrayWidth: CGFloat {
        Constants.DetailTray.width + Constants.DetailTray.glassEffectPadding * 2
    }

    /// The tray opens on the control island's side, so a rail on the right brings it in from the right.
    private var detailTrayOpensOnRight: Bool {
        guard let content = window?.contentView else { return false }
        return detailTrayLeading + detailTrayWidth / 2 > content.bounds.midX
    }

    /// Where the tray waits while hidden: wholly past the window edge on its side.
    private var detailTrayHiddenTransform: CATransform3D {
        guard detailTrayOpensOnRight, let content = window?.contentView else {
            return CATransform3DMakeTranslation(-(detailTrayLeading + detailTrayWidth), 0, 0)
        }
        return CATransform3DMakeTranslation(content.bounds.maxX - detailTrayLeading, 0, 0)
    }

    private func updateDetailTrayPosition() {
        guard let content = window?.contentView else { return }
        let glassLeading = DetailTrayLayout.leading(
            in: content.bounds,
            controlRail: windowState.controlIsland.railFrame,
            onRight: windowState.controlIsland.placement.opensLeft(in: content.bounds),
            width: Constants.DetailTray.width,
        )
        detailTrayLeadingConstraint?.constant = glassLeading - Constants.DetailTray.glassEffectPadding
        content.layoutSubtreeIfNeeded()
        updateDetailTrayTrailingEdge()
    }

    // MARK: - Trailing Edge Tracking

    /// Updates the trailing edge position exposed to SwiftUI.
    ///
    /// Called whenever the tray position changes. SwiftUI views like `LinkHoverPreviewView`
    /// use this value to avoid overlapping with the tray.
    private func updateDetailTrayTrailingEdge() {
        // A tray on the right leaves the leading side, where link previews sit, clear.
        guard isDetailTrayVisible, !detailTrayOpensOnRight else {
            windowState.detailTrayTrailingEdge = 0
            return
        }

        windowState.detailTrayTrailingEdge = detailTrayLeading + detailTrayWidth
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
