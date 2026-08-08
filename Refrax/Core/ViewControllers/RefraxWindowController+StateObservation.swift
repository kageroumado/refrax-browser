import AppKit
import Combine

// MARK: - State Observation

extension RefraxWindowController {
    /// Observes sidebar collapse state and manages overlay/tracking region accordingly.
    /// Also syncs collapse state to WindowState for SwiftUI views.
    func observeSidebarState() {
        let sidebarItem = splitViewController.splitViewItems[0]

        sidebarItem.publisher(for: \.isCollapsed)
            .sink { [weak self] isCollapsed in
                guard let self, !self.isRestoringState else { return }

                windowState.isSidebarCollapsed = isCollapsed

                // AppKit only dirties restorable state on window changes it can
                // see (frame, ordering) — sidebar collapse isn't one of them
                window?.invalidateRestorableState()

                if isCollapsed {
                    let currentWidth = sidebarItem.viewController.view.frame.width
                    if currentWidth > 0 {
                        lastCollapsedThickness = currentWidth
                        windowState.sidebarThickness = currentWidth
                    }

                    if isAnimatingCollapse {
                        // Handle based on sidebar mode
                        let mode = windowState.effectiveSidebarMode
                        switch mode {
                        case .overlay:
                            trackingViewWidthConstraint?.constant = Constants.SidebarAnimation.activationWidth
                            updateTrackingAreaImmediately()
                            showTutorialPeek()
                        case .compact:
                            // Compact mode: disable tracking, animate compact sidebar in after collapse
                            trackingViewWidthConstraint?.constant = 0
                            updateTrackingAreaImmediately()
                            // Schedule compact overlay appearance after collapse animation
                            Task { @MainActor [weak self] in
                                try? await Task.sleep(for: .milliseconds(250))
                                self?.enterCompactSidebarMode(animated: true)
                            }
                        }
                        // Move detail tray to edge position when sidebar collapses via animation
                        animateDetailTrayToOverlayProgress(0.0, duration: Constants.DetailTray.repositionDuration)
                        return
                    }

                    enterCollapsedSidebarState(animated: true)
                } else {
                    if isTransitioningFromOverlay {
                        return
                    }

                    // Restore sidebar to its last known width when uncollapsing
                    splitViewController.splitView.setPosition(
                        lastCollapsedThickness,
                        ofDividerAt: 0,
                    )

                    sidebarExpansionTask?.cancel()
                    sidebarExpansionTask = Task { @MainActor in
                        try await Task.sleep(for: .milliseconds(300))

                        enterExpandedSidebarState(animated: true)
                    }
                }
            }
            .store(in: &cancellables)

        sidebarItem.viewController.view.publisher(for: \.frame)
            .map(\.width)
            .removeDuplicates()
            .sink { [weak self] width in
                guard let self, !self.isRestoringState else { return }
                if !sidebarItem.isCollapsed, width > 0 {
                    lastCollapsedThickness = width
                    windowState.sidebarThickness = width

                    // AppKit only dirties restorable state on window changes it
                    // can see (frame, ordering) — divider drags aren't one of them
                    window?.invalidateRestorableState()

                    // Update overlay container width constraint
                    // Container width = sidebarWidth + padding (see setupSidebarOverlayContainer docs)
                    let padding = Constants.SidebarAnimation.glassEffectPadding
                    sidebarOverlayWidthConstraint?.constant = width + padding

                    updateTrafficLightsForExpandedSidebar(animated: false)
                    // Update detail tray position to follow sidebar edge (no animation
                    // during drag - width updates continuously frame-by-frame)
                    if isDetailTrayVisible {
                        updateDetailTrayPosition(animated: false)
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// Observes inspector collapse state and width, syncs to WindowState.
    ///
    /// ## Width Preservation
    ///
    /// The width is captured whenever the inspector is visible and resized.
    /// This ensures when the user reopens the inspector, it returns to their
    /// preferred width even if they closed it in between.
    func observeInspectorState() {
        guard splitViewController.splitViewItems.count > 2 else { return }
        let inspectorItem = splitViewController.splitViewItems[2]

        inspectorItem.viewController.view.publisher(for: \.frame)
            .map(\.width)
            .removeDuplicates()
            .sink { [weak self] width in
                guard let self,
                      !self.isRestoringState,
                      !self.isUpdatingInspectorProgrammatically else { return }
                if !inspectorItem.isCollapsed, width > 0 {
                    windowState.referencePaneDockedWidth = width
                }
            }
            .store(in: &cancellables)

        inspectorItem.publisher(for: \.isCollapsed)
            .sink { [weak self] isCollapsed in
                guard let self, !self.isRestoringState else { return }
                windowState.isInspectorCollapsed = isCollapsed
            }
            .store(in: &cancellables)
    }

    func observeWindowState() {
        // Observe settings that affect window background color
        let colorSettingsChanges = Observations {
            (
                self.settings.customWindowBackgroundColorHex,
                self.settings.windowBackgroundMixAmount,
                self.settings.windowBackgroundMixMode,
                self.settings.windowBackgroundFillOpacity,
                self.settings.enableSpaceWindowColoring,
                self.settings.enableWebsiteWindowColoring,
                self.settings.websiteColorUseSolidBlend,
            )
        }
        let settingsTask = Task { @MainActor [weak self] in
            for await _ in colorSettingsChanges {
                self?.updateWindowBackground()
            }
        }
        observationTasks.append(settingsTask)

        // Observe the debounced website color for smooth transitions
        let websiteColorChanges = Observations {
            self.windowState.debouncedWebsiteColor
        }
        let websiteColorTask = Task { @MainActor [weak self] in
            for await _ in websiteColorChanges {
                self?.updateWindowBackground()
            }
        }
        observationTasks.append(websiteColorTask)

        // Observe active tab changes to update toolbar item enabled states
        // (e.g., layout mode button should be disabled for live favorites)
        let activeTabChanges = Observations {
            self.windowState.activeTabID
        }
        let activeTabTask = Task { @MainActor [weak self] in
            for await _ in activeTabChanges {
                self?.window?.toolbar?.validateVisibleItems()
            }
        }
        observationTasks.append(activeTabTask)

        // Observe inspector collapsed state from external sources.
        // When the reference pane is moved to a window, it sets isInspectorCollapsed = true
        // directly on windowState. This observation syncs that to the actual split view.
        let inspectorCollapseChanges = Observations {
            self.windowState.isInspectorCollapsed
        }
        let inspectorCollapseTask = Task { @MainActor [weak self] in
            for await isCollapsed in inspectorCollapseChanges {
                guard let self else { return }
                // Only update if the split view state differs from the desired state
                // to avoid infinite loops with the reverse observation in observeInspectorState
                guard splitViewController.splitViewItems.count > 2 else { continue }
                let inspectorItem = splitViewController.splitViewItems[2]
                if inspectorItem.isCollapsed != isCollapsed {
                    updateInspectorCollapsed(isCollapsed, animated: true)
                }
            }
        }
        observationTasks.append(inspectorCollapseTask)

        // Force inspector hosting view to display when reference tab content changes.
        // NSSplitViewItem's hosting view doesn't always commit a display pass when
        // SwiftUI content transitions between conditional branches (e.g., empty state
        // to WebViewContainer). This observation ensures the hosting view re-renders.
        let refTabChanges = Observations {
            self.windowState.activeReferenceTabID
        }
        let refTabTask = Task { @MainActor [weak self] in
            for await _ in refTabChanges {
                self?.invalidateInspectorDisplay()
            }
        }
        observationTasks.append(refTabTask)
    }

    /// Observes space lock state to hide/show toolbar and traffic lights.
    ///
    /// When a locked space requires authentication, the lock overlay covers the
    /// entire window including the sidebar. The toolbar buttons and traffic lights
    /// should also be hidden to prevent any visual elements from appearing above
    /// the lock overlay (which is SwiftUI, while toolbar is AppKit).
    ///
    /// ## Behavior
    ///
    /// - **Space locked**: Hide toolbar items immediately (traffic lights stay visible)
    /// - **Space unlocked**: Restore toolbar items
    ///
    /// This uses `hideToolbarItemsInstantly()` / `showToolbarItemsInstantly()`
    /// rather than animated transitions since the lock overlay transition should
    /// be the primary visual focus.
    ///
    /// ## Observation Strategy
    ///
    /// We observe `isSpaceLocked` (a boolean) rather than `lockedSpaceRequiringAuth`
    /// (a Space?) to avoid Sendable issues with PersistentModel objects in async
    /// observation contexts.
    func observeSpaceLockState() {
        let lockChanges = Observations {
            self.windowState.isSpaceLocked
        }

        let task = Task { @MainActor [weak self] in
            for await _ in lockChanges {
                guard let self else { return }
                updateWindowChromeForLockState()
            }
        }
        observationTasks.append(task)
    }

    /// Updates toolbar and overlay visibility based on lock state.
    ///
    /// Hides toolbar items and sidebar overlay when a locked space is active,
    /// preventing them from appearing above the SwiftUI lock overlay. Traffic
    /// lights remain visible so the user can still close/minimize/fullscreen
    /// the window.
    func updateWindowChromeForLockState() {
        // Bump version counter to ensure the SwiftUI overlay re-renders.
        // This Observations handler fires reliably; the counter bridges
        // that to SwiftUI views that observe WindowState directly.
        windowState.spaceLockVersion &+= 1

        if windowState.isSpaceLocked {
            // Hide toolbar items when locked (traffic lights stay visible)
            hideToolbarItemsInstantly()

            // Hide sidebar overlay and disable hover tracking
            hideTask?.cancel()
            hideTask = nil
            cancelTutorialPeek()
            hideSidebarOverlayInstantly()
            trackingViewWidthConstraint?.constant = 0
            updateTrackingAreaImmediately()
            isAnimatingToVisible = false
            isOverlayTriggered = false
            sidebarTrackingView?.isOverlayTriggered = false
        } else {
            // Restore state when unlocked
            let sidebarItem = splitViewController.splitViewItems[0]
            if sidebarItem.isCollapsed {
                // Sidebar collapsed: restore hover tracking or compact mode
                let mode = windowState.effectiveSidebarMode
                switch mode {
                case .overlay:
                    trackingViewWidthConstraint?.constant = Constants.SidebarAnimation.activationWidth
                    updateTrackingAreaImmediately()
                case .compact:
                    enterCompactSidebarMode(animated: false)
                }
            } else {
                // Sidebar expanded: restore toolbar items
                showToolbarItemsInstantly()
            }
        }
    }

    /// Observes the active webpage's effective color for website window coloring.
    ///
    /// This observation tracks changes to the active tab's theme color and
    /// sampled page top color, forwarding them to WindowState for debouncing.
    func observeWebsiteColor() {
        let colorChanges = Observations {
            self.windowState.activeWebPage?.effectiveWindowColor
        }
        let task = Task { @MainActor [weak self] in
            for await _ in colorChanges {
                guard let self else { return }
                let color = windowState.activeWebPage?.effectiveWindowColor
                windowState.updateWebsiteColor(color)
            }
        }
        observationTasks.append(task)

        // Also observe active tab changes to update/clear website color
        let tabChanges = Observations {
            self.windowState.activeTabID
        }
        let tabTask = Task { @MainActor [weak self] in
            for await _ in tabChanges {
                guard let self else { return }
                // Get the new active page's color
                let color = windowState.activeWebPage?.effectiveWindowColor
                windowState.updateWebsiteColor(color)
            }
        }
        observationTasks.append(tabTask)
    }

    /// Observes sidebar mode changes and updates overlay container width.
    ///
    /// ## Mode Handling
    ///
    /// - **Overlay mode**: Container width = `sidebarThickness + padding`. Overlay appears on hover.
    /// - **Compact mode**: Container width = `compactWidth + padding`. Overlay is always visible.
    ///
    /// When the mode changes, this observer:
    /// 1. Updates the overlay container width constraint
    /// 2. For compact mode: Shows the overlay immediately (bypasses hover trigger)
    /// 3. For overlay mode: Hides the overlay (reverts to hover behavior)
    func observeSidebarMode() {
        let modeChanges = Observations {
            self.windowState.effectiveSidebarMode
        }

        let task = Task { @MainActor [weak self] in
            for await _ in modeChanges {
                guard let self else { return }
                updateSidebarOverlayForMode()
            }
        }
        observationTasks.append(task)
    }

    /// Updates the sidebar overlay when the effective mode changes.
    ///
    /// Handles animated transitions between overlay and compact modes while the
    /// sidebar is collapsed. Does nothing if sidebar is expanded.
    ///
    /// ## Transitions
    ///
    /// - **Overlay → Compact**: Hide current overlay, disable tracking, animate compact in
    /// - **Compact → Overlay**: Animate compact out, enable tracking, show peek if needed
    func updateSidebarOverlayForMode() {
        let sidebarItem = splitViewController.splitViewItems[0]
        let isCollapsed = sidebarItem.isCollapsed

        // Only handle mode changes when sidebar is collapsed
        guard isCollapsed else { return }

        let mode = windowState.effectiveSidebarMode

        switch mode {
        case .overlay:
            // Switching to overlay mode: hide compact, enable tracking
            transitionToOverlayMode()
        case .compact:
            // Switching to compact mode: disable tracking, show compact
            transitionToCompactMode()
        }
    }

    /// Transitions from compact mode to overlay mode.
    ///
    /// Animates the compact overlay out, then enables hover tracking and shows
    /// the tutorial peek if it hasn't been shown yet.
    private func transitionToOverlayMode() {
        overlayAnimationGeneration &+= 1
        let generationAtStart = overlayAnimationGeneration

        // Exit compact traffic light mode first
        exitCompactTrafficLightMode(animated: true)

        // Hide edge extension background
        hideEdgeExtensionBackground(animated: true)

        // First, animate the compact overlay out
        let duration = Constants.SidebarAnimation.hideSpringResponse
        animateSidebarOverlay(visible: false, duration: duration)

        // After animation completes, set up overlay mode
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(duration * 1_000) + 50))
            guard let self, generationAtStart == overlayAnimationGeneration else { return }

            // Update width for overlay mode
            let padding = Constants.SidebarAnimation.glassEffectPadding
            sidebarOverlayWidthConstraint?.constant = windowState.sidebarThickness + padding

            // Enable hover tracking
            trackingViewWidthConstraint?.constant = Constants.SidebarAnimation.activationWidth
            updateTrackingAreaImmediately()

            // Show tutorial peek if not shown
            showTutorialPeek()
        }
    }

    /// Transitions from overlay mode to compact mode.
    ///
    /// Cancels any active overlay/tracking, updates width, then animates the
    /// compact overlay into view.
    private func transitionToCompactMode() {
        overlayAnimationGeneration &+= 1
        let generationAtStart = overlayAnimationGeneration

        // Cancel any active hover interaction
        cancelTutorialPeek()
        hideTask?.cancel()
        hideTask = nil

        // If overlay was triggered or animating, hide it first
        if isOverlayTriggered || isAnimatingToVisible {
            let duration = Constants.SidebarAnimation.hideSpringResponse
            animateSidebarOverlay(visible: false, duration: duration)
            animateWindowChrome(forOverlayProgress: 0.0, duration: duration)
            animateDetailTrayToOverlayProgress(0.0, duration: duration)

            // After hide animation, show compact
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(duration * 1_000) + 50))
                guard let self, generationAtStart == overlayAnimationGeneration else { return }
                enterCompactSidebarMode(animated: true)
            }
        } else {
            // No overlay visible, directly enter compact mode
            enterCompactSidebarMode(animated: true)
        }

        // Disable hover tracking
        trackingViewWidthConstraint?.constant = 0
        updateTrackingAreaImmediately()

        isAnimatingToVisible = false
        isOverlayTriggered = false
        sidebarTrackingView?.isOverlayTriggered = false
    }

    /// Enters compact sidebar mode, optionally with animation.
    ///
    /// Updates the overlay width for compact mode and shows the compact sidebar.
    /// Uses the same animation system as `snapOverlayToVisible()` for consistency.
    /// Also sets up iPadOS-style compact traffic lights.
    ///
    /// - Parameter animated: Whether to animate the compact sidebar appearance.
    func enterCompactSidebarMode(animated: Bool) {
        let padding = Constants.SidebarAnimation.glassEffectPadding
        let compactContainerWidth = Constants.SidebarAnimation.compactWidth + padding
        sidebarOverlayWidthConstraint?.constant = compactContainerWidth

        // Update trailing edge so link preview avoids the compact strip
        windowState.sidebarOverlayTrailingEdge = compactContainerWidth

        // Cancel any pending operations
        hideTask?.cancel()
        hideTask = nil

        if animated {
            // Use the same animation as snapOverlayToVisible for consistency
            overlayAnimationGeneration &+= 1
            let duration = Constants.SidebarAnimation.snapDuration
            animateSidebarOverlay(visible: true, duration: duration)
            // Note: We don't animate window chrome or detail tray for compact mode
        } else {
            // Show immediately without animation
            guard let container = sidebarOverlayContainer, let layer = container.layer else { return }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.removeAnimation(forKey: "sidebarOverlayAnimation")
            layer.transform = CATransform3DIdentity
            CATransaction.commit()

            container.isHidden = false
        }

        // Compact mode doesn't use the hover tracking state
        isAnimatingToVisible = false
        isOverlayTriggered = false
        sidebarTrackingView?.isOverlayTriggered = false

        // Set up iPadOS-style compact traffic lights
        enterCompactTrafficLightMode(animated: animated)

        // Show edge extension background and trigger color sampling
        showEdgeExtensionBackground(animated: animated)
        triggerEdgeSampling()

        // Ensure scroll and navigation observers are active for this page.
        // These may not have been created if the sidebar was expanded at window setup time.
        observeActivePageScroll()
        observeActivePageNavigation()

        // Reposition detail tray for compact width
        updateDetailTrayPosition(animated: animated)
    }

    func updateWindowBackground() {
        let background = windowState.resolvedBackground
        let (color, source) = (background.color, background.source)

        // Update fill opacity from settings
        backgroundView.updateFillOpacity(settings.windowBackgroundFillOpacity)

        // Determine the blend mode based on color source and settings
        let useSolidMode = source == .website && settings.websiteColorUseSolidBlend

        if useSolidMode {
            // Solid mode: fully opaque color covering the background
            backgroundView.updateTint(color: color.cgColor, compositingFilter: nil)
        } else {
            // Blended mode: semi-transparent with compositing filter
            let tintColor = color.cgColor.copy(alpha: settings.windowBackgroundMixAmount)
            backgroundView.updateTint(color: tintColor, compositingFilter: settings.windowBackgroundMixMode.makeCIFilter())
        }

        // Update sidebar overlay glass tint
        updateSidebarOverlayTint()
    }

    /// Updates the sidebar overlay glass view tint to match the window background color.
    func updateSidebarOverlayTint() {
        guard let glassView = sidebarOverlayGlassView else { return }
        let color = windowState.backgroundColor.nsColor
        let multiplier = Constants.Opacity.tintOpacityMultiplier
        let alpha = settings.windowBackgroundMixAmount * multiplier
        glassView.tintColor = color.withAlphaComponent(alpha)
    }

    /// Update inspector item based on collapsed state.
    ///
    /// ## Width Preservation
    ///
    /// When expanding the inspector, we restore to the saved `referencePaneDockedWidth`
    /// so it opens to the user's preferred width.
    ///
    /// ## NSSplitView Cache Priming
    ///
    /// NSSplitView caches the divider position when an item is collapsed and animates
    /// back to that cached position when uncollapsing. During window restoration, this
    /// cache can contain a stale value (e.g., the initial 300px from window setup)
    /// instead of the user's saved width.
    ///
    /// To fix this, we "prime" the cache before animating: briefly uncollapse, set the
    /// target position, and collapse again—all without animation. This updates the
    /// internal cache so the subsequent animated uncollapse restores to the correct width.
    ///
    /// - Parameter collapsed: Whether the inspector should be collapsed.
    /// - Parameter animated: Whether to animate the change. Set to false during restoration.
    func updateInspectorCollapsed(_ collapsed: Bool, animated: Bool = true) {
        guard splitViewController.splitViewItems.count > 2 else { return }
        let inspectorItem = splitViewController.splitViewItems[2]

        // Prevent the frame observer from updating referencePaneDockedWidth during animation
        isUpdatingInspectorProgrammatically = true

        if collapsed {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animated ? 0.3 : 0
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                inspectorItem.animator().isCollapsed = true
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    self?.isUpdatingInspectorProgrammatically = false
                }
            }
        } else {
            let savedWidth = windowState.referencePaneDockedWidth
            let targetPosition = splitViewController.view.bounds.width - savedWidth

            // Prime the cache: uncollapse -> set position -> collapse (all instant, no animation)
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.allowsImplicitAnimation = false
            NSAnimationContext.current.duration = 0

            inspectorItem.isCollapsed = false
            splitViewController.splitView.setPosition(targetPosition, ofDividerAt: 1)
            inspectorItem.isCollapsed = true

            NSAnimationContext.endGrouping()

            // Now animate the uncollapse - it restores to our primed target position
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animated ? 0.3 : 0
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true

                inspectorItem.animator().isCollapsed = false
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    self?.isUpdatingInspectorProgrammatically = false
                    // Force display after expansion — the hosting view may not
                    // commit a display pass after the cache-priming sequence.
                    self?.invalidateInspectorDisplay()
                }
            }
        }
    }

    /// Forces the inspector's hosting view to re-render.
    ///
    /// Works around an NSSplitViewItem issue where the hosting view doesn't
    /// commit a display pass when SwiftUI content transitions between
    /// conditional branches internally (e.g., empty state → WebViewContainer).
    private func invalidateInspectorDisplay() {
        guard splitViewController.splitViewItems.count > 2 else { return }
        let inspectorView = splitViewController.splitViewItems[2].viewController.view
        inspectorView.needsLayout = true
        inspectorView.needsDisplay = true
    }
}

// MARK: - Sidebar State Management

extension RefraxWindowController {
    /// Configures the UI for collapsed sidebar state.
    ///
    /// This method sets up everything needed when the sidebar is collapsed:
    /// - Activates the hover tracking region for sidebar overlay
    /// - Hides traffic lights and toolbar items (animated or instant)
    /// - Shows tutorial peek animation (if not shown before)
    /// - Moves detail tray to edge position (overlay hidden)
    ///
    /// - Parameter animated: Whether to animate the window chrome hiding.
    ///   Use `false` during restoration for instant state setup.
    func enterCollapsedSidebarState(animated: Bool) {
        overlayAnimationGeneration &+= 1

        let mode = windowState.effectiveSidebarMode

        // Set tracking width based on mode
        switch mode {
        case .overlay:
            trackingViewWidthConstraint?.constant = Constants.SidebarAnimation.activationWidth
        case .compact:
            // Disable tracking in compact mode
            trackingViewWidthConstraint?.constant = 0
        }
        updateTrackingAreaImmediately()

        isAnimatingToVisible = false
        isOverlayTriggered = false
        sidebarTrackingView?.isOverlayTriggered = false

        // Initially hide overlay - compact mode will animate it in separately
        hideSidebarOverlayInstantly()

        hideTask?.cancel()
        hideTask = nil
        sidebarExpansionTask?.cancel()
        sidebarExpansionTask = nil

        if let adapter = splitViewSidebarTrackingAdapter {
            adapter.overrideDividerPosition = windowState.sidebarThickness + sidebarDividerOffset
        }

        // Move detail tray to edge position when sidebar collapses
        if animated {
            animateDetailTrayToOverlayProgress(0.0, duration: Constants.DetailTray.repositionDuration)
        } else {
            setDetailTrayToOverlayProgressInstantly(0.0)
        }

        if animated {
            let currentGen = overlayAnimationGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                animateWindowChromeEased(forOverlayProgress: 0.0)

                // After animation completes, set toolbar items to isHidden to prevent clicks
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self, currentGen == overlayAnimationGeneration else { return }
                    hideToolbarItemsInstantly()
                }

                // Only show tutorial peek in overlay mode
                if mode == .overlay {
                    showTutorialPeek()
                } else {
                    // Compact mode: animate sidebar in after a short delay
                    enterCompactSidebarMode(animated: true)
                }
            }
        } else {
            cancelChromeAnimations()
            applyTrafficLightVisibility(0.0, animated: false)
            hideToolbarItemsInstantly()

            // For non-animated compact mode entry, show immediately
            if mode == .compact {
                enterCompactSidebarMode(animated: false)
            }
        }
    }

    /// Configures the UI for expanded sidebar state.
    ///
    /// This method sets up everything needed when the sidebar is visible:
    /// - Deactivates the hover tracking region
    /// - Restores traffic lights and toolbar items to visible positions
    /// - Clears any pending overlay animations
    /// - Moves detail tray to expanded sidebar position (16px gap)
    ///
    /// - Parameter animated: Whether to animate the window chrome showing.
    ///   Use `false` during restoration for instant state setup.
    func enterExpandedSidebarState(animated: Bool) {
        overlayAnimationGeneration &+= 1

        trackingViewWidthConstraint?.constant = 0
        updateTrackingAreaImmediately()

        isAnimatingToVisible = false
        isOverlayTriggered = false
        sidebarTrackingView?.isOverlayTriggered = false

        hideSidebarOverlayInstantly()

        cancelTutorialPeek()
        hideTask?.cancel()
        hideTask = nil
        sidebarExpansionTask?.cancel()
        sidebarExpansionTask = nil

        // Exit compact traffic light mode if active
        exitCompactTrafficLightMode(animated: animated)

        restoreSplitViewSidebarTracking()

        // Move detail tray to expanded sidebar position (with 16px gap)
        updateDetailTrayPosition(animated: animated)

        if animated {
            // Don't call clearToolbarItemTransforms() first - it would reset alpha/transform
            // to visible state, leaving nothing to animate. updateTrafficLightsForExpandedSidebar
            // sets isHidden=false and animates from the current (hidden) state.
            updateTrafficLightsForExpandedSidebar(animated: true)
        } else {
            cancelChromeAnimations()
            showToolbarItemsInstantly()
            applyTrafficLightVisibility(1.0, animated: false)
        }

        // Hide edge extension background when sidebar expands
        hideEdgeExtensionBackground(animated: animated)
    }
}

// MARK: - Edge Extension Background

extension RefraxWindowController {
    /// Shows the edge extension background with sampled colors.
    ///
    /// - Parameter animated: Whether to animate the appearance.
    func showEdgeExtensionBackground(animated: Bool) {
        guard let backgroundView = edgeExtensionBackgroundView else { return }

        backgroundView.isHidden = false
        backgroundView.setVisible(true, animated: animated)

        // Start observing sampled colors if not already observing
        observeEdgeSamplerColors()
    }

    /// Hides the edge extension background.
    ///
    /// - Parameter animated: Whether to animate the disappearance.
    func hideEdgeExtensionBackground(animated: Bool) {
        guard let backgroundView = edgeExtensionBackgroundView else { return }

        if animated {
            backgroundView.setVisible(false, animated: true)
            // Hide after animation completes
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.edgeExtensionBackgroundView?.isHidden = true
            }
        } else {
            backgroundView.isHidden = true
            backgroundView.alphaValue = 0
        }

        // Clear sampled colors
        edgeSampler.clearColors()
    }

    /// Triggers edge color sampling from the current active webview.
    ///
    /// Waits for page render before sampling to avoid capturing blank/loading state.
    func triggerEdgeSampling() {
        guard let webPage = windowState.activeWebPage else { return }

        // Wait for page to render before sampling
        Task { @MainActor [weak self] in
            // Wait for WebKit's next presentation update
            await webPage.backingWebView.waitForPresentationUpdate()
            // Additional delay for page content to fully render (first paint may be blank)
            try? await Task.sleep(for: .milliseconds(100))
            guard let self else { return }
            edgeSampler.sampleEdgeColors(from: webPage)
        }
    }

    /// Triggers debounced edge color sampling (for scroll events).
    func triggerDebouncedEdgeSampling() {
        guard windowState.effectiveSidebarMode == .compact,
              windowState.isSidebarCollapsed,
              let webPage = windowState.activeWebPage else { return }
        edgeSampler.sampleEdgeColors(from: webPage)
    }

    /// Observes sampled colors and updates the background view.
    private func observeEdgeSamplerColors() {
        // Observe all color properties - any change triggers an update
        let colorChanges = Observations {
            // Access all to trigger on any change
            _ = self.edgeSampler.fullWidthColors
            _ = self.edgeSampler.edgeStripColors
            _ = self.edgeSampler.nearEdgeColors
            _ = self.edgeSampler.midEdgeColors
            _ = self.edgeSampler.topCornerColor
            _ = self.edgeSampler.bottomCornerColor
        }

        let task = Task { @MainActor [weak self] in
            for await _ in colorChanges {
                guard let self else { return }
                edgeExtensionBackgroundView?.updateColors(
                    edgeSampler.fullWidthColors,
                    edgeStripColors: edgeSampler.edgeStripColors,
                    nearEdgeColors: edgeSampler.nearEdgeColors,
                    midEdgeColors: edgeSampler.midEdgeColors,
                    topCornerColor: edgeSampler.topCornerColor,
                    bottomCornerColor: edgeSampler.bottomCornerColor,
                )
            }
        }
        observationTasks.append(task)
    }

    /// Observes active tab changes to trigger re-sampling in compact mode.
    func observeActiveTabForEdgeSampling() {
        // Observe tab changes
        let tabChanges = Observations {
            self.windowState.activeTabID
        }

        let tabTask = Task { @MainActor [weak self] in
            for await _ in tabChanges {
                guard let self else { return }
                // Only sample if in compact mode with sidebar collapsed
                if windowState.effectiveSidebarMode == .compact,
                   windowState.isSidebarCollapsed {
                    triggerEdgeSampling()
                }
                // Also start observing scroll and navigation for the new active page
                observeActivePageScroll()
                observeActivePageNavigation()
            }
        }
        observationTasks.append(tabTask)

        // Initial observation for current page
        observeActivePageScroll()
        observeActivePageNavigation()
    }

    /// Observes scroll position changes on the active page for edge re-sampling.
    ///
    /// Safe to call at any time — the inner loop checks compact+collapsed before sampling.
    func observeActivePageScroll() {
        let scrollChanges = Observations {
            self.windowState.activeWebPage?.scrollOffsetY
        }

        let scrollTask = Task { @MainActor [weak self] in
            for await _ in scrollChanges {
                guard let self else { return }
                // Debounced re-sampling on scroll
                if windowState.effectiveSidebarMode == .compact,
                   windowState.isSidebarCollapsed {
                    triggerDebouncedEdgeSampling()
                }
            }
        }
        observationTasks.append(scrollTask)
    }

    /// Observes navigation completion on the active page for edge re-sampling.
    ///
    /// Safe to call at any time — the inner loop checks compact+collapsed before sampling.
    func observeActivePageNavigation() {
        // Observe isLoading transitions - sample when loading completes
        let loadingChanges = Observations {
            self.windowState.activeWebPage?.isLoading
        }

        let navigationTask = Task { @MainActor [weak self] in
            var previouslyLoading = false
            for await isLoading in loadingChanges {
                guard let self else { return }
                // Trigger sampling when loading finishes (transition from true to false)
                if previouslyLoading, isLoading == false {
                    if windowState.effectiveSidebarMode == .compact,
                       windowState.isSidebarCollapsed {
                        triggerEdgeSampling()
                    }
                }
                previouslyLoading = isLoading ?? false
            }
        }
        observationTasks.append(navigationTask)
    }
}
