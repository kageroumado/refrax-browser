import AppKit
import SwiftUI

// MARK: - Sidebar Overlay Container View

/// Container view for the sidebar overlay that tracks cursor presence.
///
/// Similar to `DetailTrayContainerView`, this tracks when the cursor enters
/// or exits the sidebar overlay area to properly block WebKit mouse events.
///
/// The overlay slides in by translating its layer, which AppKit ignores for hit
/// testing and tracking areas: the frame always spans the full sidebar width. Both
/// are therefore clipped to the part of the overlay actually on screen, so a click
/// beside a barely-revealed sidebar reaches the page instead of an invisible tab.
final class SidebarOverlayContainerView: NSView {
    private var trackingArea: NSTrackingArea?

    /// Whether the cursor was last reported inside the visible part of the overlay.
    private var isCursorInside = false

    /// Called when the cursor enters or exits the visible part of the overlay.
    /// The callback receives `true` when cursor enters, `false` when it exits.
    var onCursorPresenceChanged: ((Bool) -> Void)?

    /// Current on-screen horizontal offset of the overlay, including in-flight animations.
    private var visibleTranslation: CGFloat {
        guard let layer else { return 0 }
        return (layer.presentation() ?? layer).transform.m41
    }

    /// Whether a point in the superview's coordinates lies over the visible overlay.
    private func isVisible(at point: NSPoint) -> Bool {
        !isHidden && point.x < frame.maxX + visibleTranslation && frame.contains(point)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isVisible(at: point) else { return nil }

        // SwiftUI locates clicks from the event's window position, which ignores the
        // layer translation. While the overlay is still sliding, forwarding the click
        // would hit whatever row sits there once fully open, not the one drawn under
        // the cursor, so the container absorbs it instead.
        guard abs(visibleTranslation) < 0.5 else { return self }

        return super.hitTest(point)
    }

    override func mouseDown(with _: NSEvent) {
        // Absorbs clicks on a partially revealed overlay (see `hitTest`).
    }

    /// Re-evaluates whether the cursor is over the visible overlay.
    ///
    /// Called when the overlay moves under a stationary cursor, which produces
    /// no tracking-area events.
    func refreshCursorPresence() {
        guard let window, let superview else { return }
        let location = superview.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        updateCursorPresence(isVisible(at: location))
    }

    private func updateCursorPresence(_ isInside: Bool) {
        guard isInside != isCursorInside else { return }
        isCursorInside = isInside
        onCursorPresenceChanged?(isInside)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil,
        )

        if let trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        updateCursorPresence(isVisible(at: superview?.convert(event.locationInWindow, from: nil) ?? .zero))
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursorPresence(isVisible(at: superview?.convert(event.locationInWindow, from: nil) ?? .zero))
    }

    override func mouseExited(with _: NSEvent) {
        updateCursorPresence(false)
    }
}

// MARK: - Sidebar Overlay Interaction

extension RefraxWindowController {
    /// Handles mouse movement within the sidebar tracking region.
    ///
    /// Implements a compressed activation zone (1/3 of sidebar width) with cubic ease-in
    /// for smooth, discoverable animation. The overlay snaps to fully visible once the
    /// cursor passes the midpoint of the activation zone.
    ///
    /// - Parameter locationInWindow: Current mouse position in window coordinates
    func handleMouseMoved(at locationInWindow: NSPoint) {
        let sidebarItem = splitViewController.splitViewItems[0]

        guard sidebarItem.isCollapsed else { return }

        // In compact mode, hover tracking is disabled - compact sidebar is always visible
        guard windowState.effectiveSidebarMode == .overlay else { return }

        cancelTutorialPeek()

        hideTask?.cancel()
        hideTask = nil

        let x = locationInWindow.x
        let sidebarWidth = windowState.sidebarThickness
        let activationWidth = Constants.SidebarAnimation.activationWidth

        guard x <= activationWidth else {
            if isAnimatingToVisible, !isOverlayTriggered {
                cancelOverlayAnimation()
            }
            return
        }

        if isOverlayTriggered, x <= sidebarWidth {
            return
        }

        if !isAnimatingToVisible {
            isAnimatingToVisible = true
            isOverlayTriggered = false
            sidebarTrackingView?.isOverlayTriggered = false
            removeOverlayAnimations()
            applyOverlayModeWidth()
        }

        let rawProgress = 1.0 - (x / activationWidth)

        if rawProgress >= Constants.SidebarAnimation.snapThreshold, !isOverlayTriggered {
            isOverlayTriggered = true
            sidebarTrackingView?.isOverlayTriggered = true
            trackingViewWidthConstraint?.constant = sidebarWidth
            updateTrackingAreaImmediately()
            snapOverlayToVisible()
        } else if !isOverlayTriggered {
            let easedProgress = pow(rawProgress, Constants.SidebarAnimation.easeInExponent)
            updateSidebarOverlayProgress(easedProgress)
            updateWindowChromeForOverlayTracking()
        }
    }

    /// Sizes the overlay container for the full sidebar before a hover reveal.
    ///
    /// Compact mode narrows the same container to the strip width, and not every
    /// path back to overlay mode restores it (the compact → overlay transition's
    /// reset is generation-guarded and can be superseded). Without this, the hover
    /// reveal slides out a strip-width sidebar.
    func applyOverlayModeWidth() {
        let width = windowState.sidebarThickness + Constants.SidebarAnimation.glassEffectPadding
        guard let constraint = sidebarOverlayWidthConstraint, constraint.constant != width else { return }
        constraint.constant = width
        sidebarOverlayContainer?.superview?.layoutSubtreeIfNeeded()
    }

    /// Updates the sidebar overlay container transform for cursor-follow progress.
    ///
    /// This is called during the cursor-tracking phase before snap-to-visible.
    /// No animation is applied - the overlay follows the cursor immediately.
    /// Also synchronizes the detail tray position if visible.
    ///
    /// - Parameter progress: 0 = hidden, 1 = fully visible
    func updateSidebarOverlayProgress(_ progress: CGFloat) {
        guard let container = sidebarOverlayContainer, let layer = container.layer else { return }

        let padding = Constants.SidebarAnimation.glassEffectPadding
        let containerWidth = windowState.sidebarThickness + padding
        let offset = -containerWidth * (1.0 - progress)

        if progress > 0 {
            container.isHidden = false
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: "sidebarOverlayAnimation")
        layer.transform = CATransform3DMakeTranslation(offset, 0, 0)
        CATransaction.commit()
        container.refreshCursorPresence()

        // Synchronize detail tray position with overlay
        updateDetailTrayForOverlayProgress(progress)
    }

    /// Handles mouse exiting the sidebar tracking region.
    ///
    /// If overlay is fully triggered, schedules a delayed hide with tolerance period.
    /// If still in follow-cursor phase, immediately cancels the animation.
    func handleMouseExited() {
        if isOverlayTriggered {
            scheduleHide()
        } else if isAnimatingToVisible {
            cancelOverlayAnimation()
        }
    }

    /// Schedules a delayed hide of the sidebar overlay with tolerance period.
    ///
    /// If the user's mouse re-enters the tracking zone before the tolerance expires,
    /// the hide is automatically cancelled via `handleMouseMoved`.
    func scheduleHide() {
        hideTask?.cancel()

        hideTask = Task { @MainActor in
            try await Task.sleep(for: Constants.SidebarAnimation.mouseExitTolerance)
            hideOverlay()
        }
    }

    /// Snaps the sidebar overlay to fully visible with easeInOut animation.
    ///
    /// Uses AppKit/Core Animation for the overlay container and coordinates
    /// traffic lights, toolbar items, and detail tray to slide together with the sidebar.
    func snapOverlayToVisible() {
        overlayAnimationGeneration &+= 1
        cancelChromeAnimations()

        let duration = Constants.SidebarAnimation.snapDuration

        animateSidebarOverlay(visible: true, duration: duration)
        animateWindowChrome(forOverlayProgress: 1.0, duration: duration)
        animateDetailTrayToOverlayProgress(1.0, duration: duration)
    }

    /// Hides the sidebar overlay and resets state machine.
    ///
    /// Coordinates traffic lights, toolbar items, and detail tray to slide out
    /// together with the sidebar overlay.
    func hideOverlay() {
        overlayAnimationGeneration &+= 1
        cancelChromeAnimations()

        isAnimatingToVisible = false
        isOverlayTriggered = false
        sidebarTrackingView?.isOverlayTriggered = false
        hideTask = nil

        let activationWidth = Constants.SidebarAnimation.activationWidth
        trackingViewWidthConstraint?.constant = activationWidth
        updateTrackingAreaImmediately()

        let duration = Constants.SidebarAnimation.hideSpringResponse

        animateSidebarOverlay(visible: false, duration: duration)
        animateWindowChrome(forOverlayProgress: 0.0, duration: duration)
        animateDetailTrayToOverlayProgress(0.0, duration: duration)

        // The animation drives the shared platter's alpha and transform, but AppKit
        // re-tiles the toolbar afterward and resets those, leaving the empty pill on
        // screen. Settle the hidden state with `isHidden` once the animation is done —
        // the same cleanup the click-driven collapse performs. Generation-guarded so a
        // re-triggered peek that supersedes this hide cancels it.
        let currentGen = overlayAnimationGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, currentGen == overlayAnimationGeneration else { return }
            hideToolbarItemsInstantly()
        }
    }

    /// Cancels the sidebar overlay animation and resets to hidden state.
    ///
    /// Called when the user moves their cursor out of the activation zone
    /// before reaching the snap threshold. Also resets detail tray position.
    func cancelOverlayAnimation() {
        overlayAnimationGeneration &+= 1

        isAnimatingToVisible = false
        isOverlayTriggered = false
        sidebarTrackingView?.isOverlayTriggered = false
        hideTask?.cancel()
        hideTask = nil

        let activationWidth = Constants.SidebarAnimation.activationWidth
        trackingViewWidthConstraint?.constant = activationWidth
        updateTrackingAreaImmediately()

        hideSidebarOverlayInstantly()
        resetWindowChromeInstantly()
        setDetailTrayToOverlayProgressInstantly(0.0)
    }

    /// Resets window chrome (traffic lights and toolbar items) to hidden state instantly.
    ///
    /// Called when cancelling a partial overlay animation. Unlike `hideOverlay()` which
    /// animates, this immediately sets the hidden state without animation.
    func resetWindowChromeInstantly() {
        cancelChromeAnimations()
        applyTrafficLightVisibility(0.0, animated: false)
        hideToolbarItemsInstantly()
    }

    /// Cancels in-flight chrome animations (toolbar items and traffic lights).
    ///
    /// Called before starting a new animation or resetting state to prevent
    /// the old animation's completion from interfering.
    ///
    /// This cancels both:
    /// - CABasicAnimation transform animations on toolbar items
    /// - NSAnimator alpha animations on toolbar items (by removing from runloop)
    /// - NSAnimator buttonRevealAmount animations on traffic lights
    func cancelChromeAnimations() {
        guard let toolbar = window?.toolbar else { return }

        for item in toolbar.items where sidebarToolbarItemIdentifiers.contains(item.itemIdentifier) {
            let itemViewer = item._itemViewer

            // Cancel layer transform animation
            itemViewer.layer?.removeAnimation(forKey: "transformAnimation")
            // Cancel NSAnimator alpha animation by removing all animations
            itemViewer.layer?.removeAllAnimations()

            if let platter = itemViewer.associatedPlatter {
                platter.layer?.removeAnimation(forKey: "transformAnimation")
                platter.layer?.removeAllAnimations()
            }

            if let superview = itemViewer.superview,
               NSStringFromClass(type(of: superview)).contains("Platter") {
                superview.layer?.removeAnimation(forKey: "transformAnimation")
                superview.layer?.removeAllAnimations()
            }
        }

        // Cancel traffic light buttonRevealAmount animation
        if let themeFrame, !isInFullscreen {
            themeFrame.layer?.removeAllAnimations()
        }
    }

    /// Forces layout and tracking area update on the sidebar tracking view.
    ///
    /// Called after changing `trackingViewWidthConstraint` to ensure the tracking
    /// region shrinks immediately rather than waiting for the next layout pass.
    ///
    /// The constraint is owned by the content view (superview), so we must
    /// trigger layout there first to update the tracking view's frame.
    func updateTrackingAreaImmediately() {
        guard let trackingView = sidebarTrackingView else { return }

        // Layout the superview first since it owns the width constraint
        if let superview = trackingView.superview {
            superview.layoutSubtreeIfNeeded()
        }

        trackingView.updateTrackingAreas()
    }

    /// Animates the sidebar overlay container in or out.
    ///
    /// Uses CABasicAnimation for smooth, reliable animations that sync with toolbar items.
    /// The animation completion handler checks the generation counter to ensure only
    /// the most recent animation's side effects are applied.
    ///
    /// - Parameters:
    ///   - visible: Whether to show (true) or hide (false) the overlay
    ///   - duration: Animation duration in seconds
    func animateSidebarOverlay(visible: Bool, duration: CGFloat) {
        guard let container = sidebarOverlayContainer, let layer = container.layer else { return }

        let padding = Constants.SidebarAnimation.glassEffectPadding
        let containerWidth = windowState.sidebarThickness + padding
        let hiddenTransform = CATransform3DMakeTranslation(-containerWidth, 0, 0)
        let visibleTransform = CATransform3DIdentity

        let currentTransform = layer.presentation()?.transform ?? layer.transform
        let toTransform = visible ? visibleTransform : hiddenTransform

        if visible {
            container.isHidden = false
            // Update trailing edge immediately so link preview moves out of the way
            windowState.sidebarOverlayTrailingEdge = sidebarOverlayWidthConstraint?.constant ?? 0
        }

        // Capture the generation at animation start
        let animationGeneration = overlayAnimationGeneration

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = currentTransform
        animation.toValue = toTransform
        animation.duration = CFTimeInterval(duration)
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak container, weak self] in
            guard let container, let self else { return }

            // Only apply completion effects if this animation is still current
            guard animationGeneration == overlayAnimationGeneration else { return }

            if !visible {
                container.isHidden = true
                windowState.sidebarOverlayTrailingEdge = 0
            }
            removeOverlayAnimations()
            container.refreshCursorPresence()
        }
        layer.add(animation, forKey: "sidebarOverlayAnimation")
        layer.transform = toTransform
        CATransaction.commit()
    }

    /// Removes any pending overlay animations.
    ///
    /// Called when starting a new animation sequence to prevent conflicts.
    func removeOverlayAnimations() {
        guard let layer = sidebarOverlayContainer?.layer else { return }
        layer.removeAnimation(forKey: "sidebarOverlayAnimation")
    }

    /// Shows a brief tutorial peek animation to hint at sidebar overlay feature.
    ///
    /// Animates the sidebar overlay slightly into view (60px), holds briefly,
    /// then hides it. Only shown once per app launch when sidebar is first collapsed.
    ///
    /// The peek is immediately cancelled if the user:
    /// - Moves cursor into the activation zone
    /// - Opens the sidebar
    /// - Triggers any other overlay interaction
    func showTutorialPeek() {
        guard !windowState.hasShownTutorialPeek else { return }

        tutorialPeekTask?.cancel()
        isTutorialPeekActive = false

        tutorialPeekTask = Task { @MainActor in
            try await Task.sleep(for: Constants.SidebarAnimation.tutorialPeekDelay)

            let sidebarItem = splitViewController.splitViewItems[0]
            guard sidebarItem.isCollapsed, !isAnimatingToVisible, !isOverlayTriggered else {
                return
            }

            windowState.hasShownTutorialPeek = true
            isTutorialPeekActive = true
            applyOverlayModeWidth()

            let peekProgress = Constants.SidebarAnimation.tutorialPeekDistance / windowState.sidebarThickness

            animateSidebarOverlayToProgress(peekProgress, duration: Constants.SidebarAnimation.tutorialPeekInDuration)

            try await Task.sleep(for: Constants.SidebarAnimation.tutorialPeekHoldDuration)
            guard isTutorialPeekActive else {
                isTutorialPeekActive = false
                return
            }

            isTutorialPeekActive = false
            animateSidebarOverlay(visible: false, duration: Constants.SidebarAnimation.tutorialPeekOutDuration)
        }
    }

    /// Cancels any in-progress tutorial peek animation.
    ///
    /// If the peek is currently showing, it will be hidden immediately.
    func cancelTutorialPeek() {
        guard tutorialPeekTask != nil || isTutorialPeekActive else { return }

        tutorialPeekTask?.cancel()
        tutorialPeekTask = nil

        if isTutorialPeekActive {
            isTutorialPeekActive = false
            hideSidebarOverlayInstantly()
        }
    }

    /// Animates the sidebar overlay to a specific progress value.
    ///
    /// Used for tutorial peek animation where we need partial visibility.
    /// The animation completion handler checks the generation counter to ensure only
    /// the most recent animation's side effects are applied.
    ///
    /// - Parameters:
    ///   - progress: Target progress (0 = hidden, 1 = fully visible)
    ///   - duration: Animation duration in seconds
    func animateSidebarOverlayToProgress(_ progress: CGFloat, duration: CGFloat) {
        guard let container = sidebarOverlayContainer, let layer = container.layer else { return }

        let padding = Constants.SidebarAnimation.glassEffectPadding
        let containerWidth = windowState.sidebarThickness + padding
        let offset = -containerWidth * (1.0 - progress)
        let toTransform = CATransform3DMakeTranslation(offset, 0, 0)
        let currentTransform = layer.presentation()?.transform ?? layer.transform

        if progress > 0 {
            container.isHidden = false
        }

        // Capture the generation at animation start
        let animationGeneration = overlayAnimationGeneration

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = currentTransform
        animation.toValue = toTransform
        animation.duration = CFTimeInterval(duration)
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, animationGeneration == overlayAnimationGeneration else { return }
            removeOverlayAnimations()
            sidebarOverlayContainer?.refreshCursorPresence()
        }
        layer.add(animation, forKey: "sidebarOverlayAnimation")
        layer.transform = toTransform
        CATransaction.commit()
    }

    /// Hides the sidebar overlay instantly without animation.
    ///
    /// Used during state restoration and when sidebar expands.
    /// Does NOT update the detail tray position - callers should handle that
    /// based on whether sidebar is collapsed or expanded.
    func hideSidebarOverlayInstantly() {
        guard let container = sidebarOverlayContainer, let layer = container.layer else { return }

        let padding = Constants.SidebarAnimation.glassEffectPadding
        let containerWidth = windowState.sidebarThickness + padding
        let hiddenTransform = CATransform3DMakeTranslation(-containerWidth, 0, 0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: "sidebarOverlayAnimation")
        layer.transform = hiddenTransform
        CATransaction.commit()

        container.isHidden = true
        container.refreshCursorPresence()
        windowState.sidebarOverlayTrailingEdge = 0
    }
}
