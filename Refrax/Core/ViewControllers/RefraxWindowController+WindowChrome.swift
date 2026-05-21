import AppKit

// MARK: - Window Chrome Animation

extension RefraxWindowController {
    /// Animates window chrome (traffic lights + toolbar) with easeInOut animation.
    ///
    /// Uses the specified duration for both SwiftUI (via NSAnimationContext) and
    /// Core Animation (CABasicAnimation) to keep overlay and toolbar in sync.
    ///
    /// - Parameters:
    ///   - progress: Overlay progress (0 = hidden, 1 = fully visible)
    ///   - duration: Animation duration in seconds
    func animateWindowChrome(forOverlayProgress progress: CGFloat, duration: CGFloat) {
        updateOverlaySidebarTracking(progress: 1.0)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            applyTrafficLightVisibility(progress, animated: true)
        }

        applyToolbarItemsOffset(forOverlayProgress: progress, animated: true, duration: duration)
    }

    /// Updates sidebar tracking position immediately without animation (for cursor tracking).
    ///
    /// During the cursor tracking phase, traffic lights and toolbar items stay hidden.
    /// We only update the sidebar divider position for the tracking separator, which
    /// needs to know where the "virtual" sidebar edge is even though items are hidden.
    func updateWindowChromeForOverlayTracking() {
        updateOverlaySidebarTracking(progress: 1.0)
    }

    /// Animates window chrome with an easeInOut animation (for normal sidebar expand/collapse).
    func animateWindowChromeEased(forOverlayProgress progress: CGFloat, duration: Double = 0.25) {
        updateOverlaySidebarTracking(progress: 1.0)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            applyTrafficLightVisibility(progress, animated: true)
        }

        applyToolbarItemsOffset(forOverlayProgress: progress, animated: true, duration: duration)
    }

    /// Updates traffic lights and toolbar items for the expanded sidebar state.
    ///
    /// Restores the split view tracking adapter and shows the window chrome
    /// (traffic lights and toolbar items) either animated or instantly.
    func updateTrafficLightsForExpandedSidebar(animated: Bool) {
        restoreSplitViewSidebarTracking()

        let duration: CGFloat = 0.25
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                applyTrafficLightVisibility(1.0, animated: true)
            }
            applyToolbarItemsOffset(forOverlayProgress: 1.0, animated: true, duration: duration)
        } else {
            applyTrafficLightVisibility(1.0)
            applyToolbarItemsOffset(forOverlayProgress: 1.0)
        }
    }

    /// Controls traffic light button visibility using buttonRevealAmount.
    ///
    /// Uses NSThemeFrame's `buttonRevealAmount` property which is designed for
    /// auto-hiding titlebar effects. Values range from 0.0 (hidden) to 1.0 (visible).
    ///
    /// In fullscreen mode, we don't manipulate traffic lights - AppKit's built-in
    /// edge reveal handles them.
    ///
    /// In compact sidebar mode, traffic lights are always visible (with scale transform)
    /// so we don't hide them via buttonRevealAmount.
    ///
    /// - Parameters:
    ///   - progress: Overlay progress (0 = buttons hidden, 1 = buttons visible)
    ///   - animated: Whether to use animator (for spring/linear animations)
    func applyTrafficLightVisibility(_ progress: CGFloat, animated: Bool = false) {
        guard let themeFrame else { return }

        if isInFullscreen { return }

        // In compact mode, traffic lights are always visible with their platter
        if isCompactTrafficLightModeActive {
            if animated {
                themeFrame.animator().buttonRevealAmount = 1.0
            } else {
                themeFrame.buttonRevealAmount = 1.0
            }
            return
        }

        if animated {
            themeFrame.animator().buttonRevealAmount = progress
        } else {
            themeFrame.buttonRevealAmount = progress
        }
    }

    /// Applies horizontal offset to sidebar toolbar items and their glass platters.
    ///
    /// This keeps the native toolbar buttons but slides them with the sidebar overlay.
    /// The divider position is kept at full sidebar width so AppKit doesn't relayout items.
    ///
    /// - Parameters:
    ///   - progress: Overlay progress (0 = hidden, 1 = fully visible)
    ///   - animated: Whether to animate the change
    ///   - duration: Animation duration (default 0.35s, used when animated is true)
    func applyToolbarItemsOffset(forOverlayProgress progress: CGFloat, animated: Bool = false, duration: CGFloat = 0.35) {
        guard let toolbar = window?.toolbar else { return }

        let hideOffset = toolbarItemHiddenOffset()
        let offset = hideOffset * (1.0 - progress)
        let targetAlpha: CGFloat = progress > 0.5 ? 1.0 : 0.0
        let transform = CATransform3DMakeTranslation(offset, 0, 0)

        for item in toolbar.items {
            guard sidebarToolbarItemIdentifiers.contains(item.itemIdentifier) else { continue }

            let itemViewer = item._itemViewer
            itemViewer.wantsLayer = true
            itemViewer.isHidden = false

            applyLayerTransform(to: itemViewer, transform: transform, alpha: targetAlpha, animated: animated, duration: duration)

            if let platter = itemViewer.associatedPlatter {
                platter.wantsLayer = true
                platter.isHidden = false
                applyLayerTransform(to: platter, transform: transform, alpha: targetAlpha, animated: animated, duration: duration)
            }

            if let superview = itemViewer.superview,
               NSStringFromClass(type(of: superview)).contains("Platter") {
                superview.wantsLayer = true
                superview.isHidden = false
                applyLayerTransform(to: superview, transform: transform, alpha: targetAlpha, animated: animated, duration: duration)
            }
        }

        hideGlassContainer()
    }

    /// Applies a layer transform and alpha to a view with optional animation.
    ///
    /// Uses CABasicAnimation for the transform since NSAnimationContext doesn't
    /// properly bridge to CALayer animations.
    func applyLayerTransform(to view: NSView, transform: CATransform3D, alpha: CGFloat, animated: Bool, duration: CGFloat) {
        if animated {
            if let layer = view.layer {
                let currentTransform = layer.presentation()?.transform ?? layer.transform
                let animation = CABasicAnimation(keyPath: "transform")
                animation.fromValue = currentTransform
                animation.toValue = transform
                animation.duration = CFTimeInterval(duration)
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animation.fillMode = .forwards
                animation.isRemovedOnCompletion = true
                layer.add(animation, forKey: "transformAnimation")
                layer.transform = transform
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                view.animator().alphaValue = alpha
            }
        } else {
            if let layer = view.layer {
                layer.removeAnimation(forKey: "transformAnimation")
                layer.transform = transform
            }
            view.alphaValue = alpha
        }
    }

    /// Hides the toolbar's glass container.
    ///
    /// The glass platter effects are rendered by NSGlassContainerView which is
    /// stored in NSToolbarView._glassContainer (an ivar, not a property).
    /// We always hide this container since the sidebar toolbar items are animated
    /// separately and don't need the glass effect backdrop.
    func hideGlassContainer() {
        guard let toolbarView else { return }

        guard let glassContainer = toolbarView.value(forKey: "_glassContainer") as? NSView else { return }

        glassContainer.wantsLayer = true
        glassContainer.alphaValue = 0
    }

    /// Calculates the offset needed to hide toolbar items off-screen.
    func toolbarItemHiddenOffset() -> CGFloat {
        captureTrafficLightOrigins()
        guard let frame = originalTrafficLightGroupFrame else {
            return -windowState.sidebarThickness
        }
        return -(frame.maxX + 20)
    }

    func captureTrafficLightOrigins(force: Bool = false) {
        guard let window else { return }
        if !originalTrafficLightOrigins.isEmpty, !force { return }

        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        var groupFrame: CGRect?

        for buttonType in buttonTypes {
            guard let button = window.standardWindowButton(buttonType) else { continue }
            originalTrafficLightOrigins[buttonType] = button.frame.origin

            // Calculate union of all button frames
            if let existing = groupFrame {
                groupFrame = existing.union(button.frame)
            } else {
                groupFrame = button.frame
            }
        }

        originalTrafficLightGroupFrame = groupFrame
    }

    /// Hides toolbar items instantly without animation.
    ///
    /// Uses `isHidden` instead of transforms/alpha for reliable instant hiding,
    /// especially during restoration when layers may not be set up yet.
    func hideToolbarItemsInstantly() {
        guard let toolbar = window?.toolbar else { return }

        for item in toolbar.items where sidebarToolbarItemIdentifiers.contains(item.itemIdentifier) {
            let itemViewer = item._itemViewer

            itemViewer.isHidden = true

            if let platter = itemViewer.associatedPlatter {
                platter.isHidden = true
            }

            if let superview = itemViewer.superview,
               NSStringFromClass(type(of: superview)).contains("Platter") {
                superview.isHidden = true
            }
        }

        hideGlassContainer()
    }

    /// Shows toolbar items instantly without animation.
    ///
    /// Reverses `hideToolbarItemsInstantly()` by clearing isHidden, resetting
    /// transforms to identity, and restoring alpha to 1.0.
    ///
    /// Used both for non-animated restoration and after animated sidebar expansion
    /// to clean up any residual transform state.
    func showToolbarItemsInstantly() {
        guard let toolbar = window?.toolbar else { return }

        for item in toolbar.items where sidebarToolbarItemIdentifiers.contains(item.itemIdentifier) {
            let itemViewer = item._itemViewer

            itemViewer.isHidden = false
            itemViewer.alphaValue = 1.0
            itemViewer.layer?.transform = CATransform3DIdentity

            if let platter = itemViewer.associatedPlatter {
                platter.isHidden = false
                platter.alphaValue = 1.0
                platter.layer?.transform = CATransform3DIdentity
            }

            if let superview = itemViewer.superview,
               NSStringFromClass(type(of: superview)).contains("Platter") {
                superview.isHidden = false
                superview.alphaValue = 1.0
                superview.layer?.transform = CATransform3DIdentity
            }
        }
    }

    /// Alias for `showToolbarItemsInstantly()`.
    ///
    /// Clears transforms, restores alpha, and unhides sidebar toolbar items.
    /// Called after the sidebar expand animation completes.
    func clearToolbarItemTransforms() {
        showToolbarItemsInstantly()
    }
}

// MARK: - Compact Mode Traffic Lights

extension RefraxWindowController {
    /// Sets up the compact traffic light mode with platter and scaled buttons.
    ///
    /// Creates an iPadOS-style appearance where traffic lights are scaled down
    /// with a glass platter background. The buttons expand on hover.
    ///
    /// - Parameter animated: Whether to animate the initial scale-down.
    func enterCompactTrafficLightMode(animated: Bool) {
        guard !isCompactTrafficLightModeActive else { return }
        isCompactTrafficLightModeActive = true

        // Ensure traffic lights are visible (not hidden by buttonRevealAmount)
        applyTrafficLightVisibility(1.0, animated: false)

        setupCompactTrafficLightPlatter()
        setupCompactTrafficLightHoverTracking()
        scaleTrafficLightsForCompactMode(expanded: false, animated: animated)
    }

    /// Exits compact traffic light mode, removing platter and restoring normal state.
    ///
    /// - Parameter animated: Whether to animate the restoration.
    func exitCompactTrafficLightMode(animated: Bool) {
        guard isCompactTrafficLightModeActive else { return }
        isCompactTrafficLightModeActive = false
        isCompactTrafficLightsHovered = false
        compactTrafficLightHoverCheckTask?.cancel()
        compactTrafficLightHoverCheckTask = nil

        removeCompactTrafficLightHoverTracking()
        removeCompactTrafficLightPlatter(animated: animated)
        resetTrafficLightTransforms(animated: animated)
    }

    /// Creates and positions the glass platter behind traffic lights.
    private func setupCompactTrafficLightPlatter() {
        guard let themeFrame, let window else { return }
        guard compactTrafficLightPlatter == nil else { return }

        // Get the traffic light group frame
        captureTrafficLightOrigins(force: true)
        guard let groupFrame = originalTrafficLightGroupFrame else { return }

        // Calculate platter frame with padding
        let padding = Constants.SidebarAnimation.compactTrafficLightPadding
        let height = groupFrame.height + padding * 2
        let cornerRadius = height / 2

        // The platter should encompass the traffic lights with padding
        // Position relative to titlebar
        let platterFrame = CGRect(
            x: groupFrame.minX - padding,
            y: groupFrame.minY - padding,
            width: groupFrame.width + padding * 2,
            height: groupFrame.height + padding * 2,
        )

        // Create glass effect platter
        let platter: NSView
        if let glassViewClass = NSClassFromString("NSGlassEffectView") as? NSGlassEffectView.Type {
            let glassView = glassViewClass.init()
            glassView.cornerRadius = cornerRadius
            platter = glassView
        } else {
            // Fallback to visual effect view
            let effectView = NSVisualEffectView()
            effectView.material = .hudWindow
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = cornerRadius
            effectView.layer?.masksToBounds = true
            platter = effectView
        }

        platter.frame = platterFrame
        platter.wantsLayer = true
        platter.alphaValue = 0

        // Insert below traffic lights in the titlebar view
        // The platter will transform with the buttons since they share the same container
        if let titlebarView = themeFrame.titlebarView {
            titlebarView.addSubview(platter, positioned: .below, relativeTo: nil)

            for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                if let button = window.standardWindowButton(buttonType) {
                    titlebarView.addSubview(platter, positioned: .below, relativeTo: button)
                    break
                }
            }
        }

        compactTrafficLightPlatter = platter

        // Fade in the platter
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Constants.SidebarAnimation.compactTrafficLightAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            platter.animator().alphaValue = 1.0
        }
    }

    /// Removes the compact traffic light platter.
    private func removeCompactTrafficLightPlatter(animated: Bool) {
        guard let platter = compactTrafficLightPlatter else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Constants.SidebarAnimation.compactTrafficLightAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                platter.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    platter.removeFromSuperview()
                }
            }
        } else {
            platter.removeFromSuperview()
        }

        compactTrafficLightPlatter = nil
    }

    /// Scales traffic lights for compact mode (tiny or expanded).
    ///
    /// Uses CA3DTransform on the traffic light buttons' container to achieve
    /// the iPadOS-style scaled appearance. Scaling the container ensures the
    /// buttons maintain their relative spacing.
    ///
    /// - Parameters:
    ///   - expanded: Whether traffic lights should be full size (hovered) or tiny (resting).
    ///   - animated: Whether to animate the scale change.
    func scaleTrafficLightsForCompactMode(expanded: Bool, animated: Bool) {
        guard let window else { return }

        // Find the traffic light container (common superview of all buttons)
        guard let closeButton = window.standardWindowButton(.closeButton),
              let container = closeButton.superview else { return }

        container.wantsLayer = true
        guard let layer = container.layer else { return }

        let duration = Constants.SidebarAnimation.compactTrafficLightAnimationDuration

        // Build combined scale + translation transform
        let transform: CATransform3D
        if expanded {
            transform = CATransform3DIdentity
        } else {
            let scale = Constants.SidebarAnimation.compactTrafficLightScale
            let translateX = Constants.SidebarAnimation.compactTrafficLightTranslateX
            let translateY = Constants.SidebarAnimation.compactTrafficLightTranslateY

            var t = CATransform3DMakeTranslation(translateX, translateY, 0)
            t = CATransform3DScale(t, scale, scale, 1)
            transform = t
        }

        if animated {
            let currentTransform = layer.presentation()?.transform ?? layer.transform
            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = currentTransform
            animation.toValue = transform
            animation.duration = CFTimeInterval(duration)
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = true
            layer.add(animation, forKey: "compactScaleAnimation")
            layer.transform = transform
        } else {
            layer.removeAnimation(forKey: "compactScaleAnimation")
            layer.transform = transform
        }
    }

    /// Resets the traffic light container transform to identity.
    /// The platter resets automatically since it's in the same container.
    private func resetTrafficLightTransforms(animated: Bool) {
        guard let window else { return }

        // Find the traffic light container (common superview of all buttons)
        guard let closeButton = window.standardWindowButton(.closeButton),
              let container = closeButton.superview,
              let layer = container.layer else { return }

        let duration = Constants.SidebarAnimation.compactTrafficLightAnimationDuration

        if animated {
            let currentTransform = layer.presentation()?.transform ?? layer.transform
            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = currentTransform
            animation.toValue = CATransform3DIdentity
            animation.duration = CFTimeInterval(duration)
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = true
            layer.add(animation, forKey: "compactScaleAnimation")
            layer.transform = CATransform3DIdentity
        } else {
            layer.removeAnimation(forKey: "compactScaleAnimation")
            layer.transform = CATransform3DIdentity
        }
    }

    /// Sets up hover tracking for the compact traffic light area.
    private func setupCompactTrafficLightHoverTracking() {
        guard let themeFrame else { return }
        removeCompactTrafficLightHoverTracking()

        // Calculate tracking area based on actual traffic light positions
        let padding = Constants.SidebarAnimation.compactTrafficLightPadding
        guard let groupFrame = originalTrafficLightGroupFrame else { return }

        // Tracking rect matches the platter bounds (slightly larger than traffic lights)
        let trackingRect = CGRect(
            x: groupFrame.minX - padding,
            y: groupFrame.minY - padding,
            width: groupFrame.width + padding * 2,
            height: groupFrame.height + padding * 2,
        )

        let trackingArea = NSTrackingArea(
            rect: trackingRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: ["compactTrafficLights": true],
        )

        themeFrame.titlebarView?.addTrackingArea(trackingArea)
        compactTrafficLightTrackingArea = trackingArea
    }

    /// Removes the hover tracking area for compact traffic lights.
    private func removeCompactTrafficLightHoverTracking() {
        guard let trackingArea = compactTrafficLightTrackingArea else { return }
        themeFrame?.titlebarView?.removeTrackingArea(trackingArea)
        compactTrafficLightTrackingArea = nil
    }

    /// Handles mouse entering the compact traffic light area.
    func handleCompactTrafficLightMouseEntered() {
        guard isCompactTrafficLightModeActive, !isCompactTrafficLightsHovered else { return }
        isCompactTrafficLightsHovered = true
        scaleTrafficLightsForCompactMode(expanded: true, animated: true)
        scheduleCompactTrafficLightHoverCheck()
    }

    /// Handles mouse exiting the compact traffic light area.
    func handleCompactTrafficLightMouseExited() {
        compactTrafficLightHoverCheckTask?.cancel()
        compactTrafficLightHoverCheckTask = nil
        guard isCompactTrafficLightModeActive, isCompactTrafficLightsHovered else { return }
        isCompactTrafficLightsHovered = false
        scaleTrafficLightsForCompactMode(expanded: false, animated: true)
    }

    /// Schedules a hover verification after the expand animation completes.
    ///
    /// NSTrackingArea can miss `mouseExited` events when the cursor moves very
    /// fast over a small tracking rect (~70×32 pt). This check runs after the
    /// animation duration and verifies the cursor is actually still inside the
    /// tracking area. If it has left, the shrink is triggered immediately.
    private func scheduleCompactTrafficLightHoverCheck() {
        compactTrafficLightHoverCheckTask?.cancel()
        let delay = Constants.SidebarAnimation.compactTrafficLightAnimationDuration + 0.05

        compactTrafficLightHoverCheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
            guard let self, isCompactTrafficLightsHovered else { return }
            verifyCompactTrafficLightHover()
        }
    }

    /// Checks whether the cursor is still inside the compact traffic light
    /// tracking area and triggers the shrink if it has left.
    private func verifyCompactTrafficLightHover() {
        guard let trackingArea = compactTrafficLightTrackingArea,
              let titlebarView = themeFrame?.titlebarView,
              let window else { return }

        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let titlebarPoint = titlebarView.convert(windowPoint, from: nil)

        if !trackingArea.rect.contains(titlebarPoint) {
            handleCompactTrafficLightMouseExited()
        }
    }
}
