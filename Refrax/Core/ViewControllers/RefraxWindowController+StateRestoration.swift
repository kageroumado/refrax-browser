import AppKit
import SwiftUI

// MARK: - State Restoration

extension RefraxWindowController {
    /// Encode window-specific state for restoration.
    ///
    /// ## What's Encoded (Per-Window)
    ///
    /// - Window frame (origin, size)
    /// - Sidebar: collapsed state, width
    /// - Active space ID
    /// - Window background color and mix settings
    func encodeWindowState(to state: NSCoder) {
        if let data = try? JSONEncoder().encode(windowState.readingState) {
            state.encode(data as NSData, forKey: "readingState")
        }
        let placements = windowState.floatingPlacements.filter { id, _ in
            guard let tab = tabManager.state.tab(for: id) else { return false }
            return tab.space?.dataStoreMode != .private
        }
        if let data = try? JSONEncoder().encode(placements) {
            state.encode(data as NSData, forKey: "floatingPlacements")
        }
        state.encode(windowState.controlIsland.placement.x as NSNumber, forKey: "controlIslandX")
        state.encode(windowState.controlIsland.placement.y as NSNumber, forKey: "controlIslandY")
        if let placement = windowState.fileIsland.placement {
            state.encode(placement.x as NSNumber, forKey: "fileIslandX")
            state.encode(placement.y as NSNumber, forKey: "fileIslandY")
        }
        // Encode window frame for explicit restoration.
        // AppKit's default NSWindow.restoreState doesn't reliably restore frame
        // when the window is created with .zero contentRect via NSWindowRestoration.
        if let frame = window?.frame {
            state.encode(frame.origin.x as NSNumber, forKey: "windowFrameX")
            state.encode(frame.origin.y as NSNumber, forKey: "windowFrameY")
            state.encode(frame.size.width as NSNumber, forKey: "windowFrameWidth")
            state.encode(frame.size.height as NSNumber, forKey: "windowFrameHeight")
        }

        let sidebarItem = splitViewController.splitViewItems[0]

        state.encode(sidebarItem.isCollapsed as NSNumber, forKey: "sidebarCollapsed")

        let sidebarWidth = sidebarItem.isCollapsed ? lastCollapsedThickness : sidebarItem.viewController.view.frame.width
        state.encode(sidebarWidth as NSNumber, forKey: "sidebarWidth")

        if let spaceID = windowState.activeSpaceID {
            state.encode(spaceID.uuidString as NSString, forKey: "activeSpaceID")
        }

        let bgColor = windowState.backgroundColor
        state.encode(bgColor.taggedString as NSString, forKey: "backgroundColorHex")
        state.encode(settings.windowBackgroundMixAmount as NSNumber, forKey: "backgroundMixAmount")
        state.encode(settings.windowBackgroundMixMode.rawValue as NSString, forKey: "backgroundMixMode")
    }

    /// Decode and restore window-specific state
    ///
    /// ## Restoration Order
    ///
    /// 1. Restore window frame (must happen first — split view positions depend on window width)
    /// 2. Restore sidebar (width, collapsed state)
    /// 3. Restore window background color
    func decodeWindowState(from state: NSCoder) {
        isRestoringState = true
        defer { isRestoringState = false }
        if let data = state.decodeObject(of: NSData.self, forKey: "readingState") as Data? {
            restoredReadingState = try? JSONDecoder().decode(WindowReadingState.self, from: data)
        }
        if let data = state.decodeObject(of: NSData.self, forKey: "floatingPlacements") as Data?,
           let placements = try? JSONDecoder().decode([Tab.ID: FloatingTabPlacement].self, from: data) {
            windowState.floatingPlacements = placements
        }

        if let x = state.decodeObject(of: NSNumber.self, forKey: "controlIslandX")?.doubleValue,
           let y = state.decodeObject(of: NSNumber.self, forKey: "controlIslandY")?.doubleValue {
            windowState.controlIsland.placement = ControlIslandPlacement(x: x, y: y)
        }
        if let x = state.decodeObject(of: NSNumber.self, forKey: "fileIslandX")?.doubleValue,
           let y = state.decodeObject(of: NSNumber.self, forKey: "fileIslandY")?.doubleValue {
            windowState.fileIsland.placement = ControlIslandPlacement(x: x, y: y)
        }

        // Restore window frame before split view positions, since divider
        // calculations depend on the window's width being correct.
        if let frameX = state.decodeObject(of: NSNumber.self, forKey: "windowFrameX")?.doubleValue,
           let frameY = state.decodeObject(of: NSNumber.self, forKey: "windowFrameY")?.doubleValue,
           let frameWidth = state.decodeObject(of: NSNumber.self, forKey: "windowFrameWidth")?.doubleValue,
           let frameHeight = state.decodeObject(of: NSNumber.self, forKey: "windowFrameHeight")?.doubleValue {
            applyFrame(NSRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight))
        }

        let sidebarWidth = state.decodeObject(of: NSNumber.self, forKey: "sidebarWidth")?.doubleValue
            ?? Constants.Layout.sidebarDefaultWidth
        let sidebarCollapsed = state.decodeObject(of: NSNumber.self, forKey: "sidebarCollapsed")?.boolValue ?? false

        applyChrome(sidebarWidth: sidebarWidth, sidebarCollapsed: sidebarCollapsed)

        if let spaceIDString = state.decodeObject(of: NSString.self, forKey: "activeSpaceID") as String?,
           let spaceID = UUID(uuidString: spaceIDString) {
            windowState.activeSpaceID = spaceID
        }

        if let colorHex = state.decodeObject(of: NSString.self, forKey: "backgroundColorHex") as String?,
           let colorComponents = Color.resolveStoredColorComponents(colorHex) {
            let mixAmount = state.decodeObject(of: NSNumber.self, forKey: "backgroundMixAmount")?.doubleValue ?? 0.15
            let mixModeRaw = state.decodeObject(of: NSString.self, forKey: "backgroundMixMode") as String? ?? ColorMixMode.softLight.rawValue
            let mixMode = ColorMixMode(rawValue: mixModeRaw) ?? .softLight

            backgroundView.updateTint(
                color: colorComponents.cgColor.copy(alpha: mixAmount),
                compositingFilter: mixMode.makeCIFilter(),
            )
        }
    }

    /// Applies geometry to a freshly created window outside the AppKit
    /// restoration path (Dock click, Cmd+N, first launch).
    ///
    /// Must be called before `showWindow(_:)` so the window appears at its
    /// final frame.
    func applyInitialGeometry(_ geometry: SavedWindowGeometry) {
        isRestoringState = true
        defer { isRestoringState = false }

        applyFrame(geometry.frame)

        let sidebarWidth = geometry.sidebarWidth.clamped(
            to: Constants.Layout.sidebarMinWidth ... Constants.Layout.sidebarMaxWidth,
        )

        applyChrome(sidebarWidth: sidebarWidth, sidebarCollapsed: geometry.isSidebarCollapsed)
    }

    /// Sets the window frame, validating it against connected screens.
    private func applyFrame(_ frame: NSRect) {
        let isVisible = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(frame)
        }

        if isVisible {
            window?.setFrame(frame, display: false)
        } else {
            // Screen configuration changed — keep the size but center on the main screen
            window?.setContentSize(frame.size)
            window?.center()
        }
    }

    /// Applies sidebar width and collapse state, syncing
    /// split view positions, `WindowState`, and the overlay width constraint,
    /// then applies the matching sidebar UI (traffic lights, toolbar items)
    /// before the window becomes visible to prevent a flash of incorrect state.
    private func applyChrome(
        sidebarWidth: CGFloat,
        sidebarCollapsed: Bool,
    ) {
        let sidebarItem = splitViewController.splitViewItems[0]

        lastCollapsedThickness = sidebarWidth
        windowState.sidebarThickness = sidebarWidth

        // Container width = sidebarWidth + padding (see setupSidebarOverlayContainer docs)
        let padding = Constants.SidebarAnimation.glassEffectPadding
        sidebarOverlayWidthConstraint?.constant = sidebarWidth + padding

        sidebarItem.isCollapsed = windowState.usesFloatingTabs || sidebarCollapsed
        windowState.isSidebarCollapsed = sidebarItem.isCollapsed

        if !sidebarItem.isCollapsed {
            splitViewController.splitView.setPosition(sidebarWidth, ofDividerAt: 0)
        }

        applySidebarStateUI()
    }

    /// Completes window initialization after DB restoration.
    ///
    /// Called after `restoreFromPersistence()` to load tabs and reapply colors
    /// (colors may have changed via iCloud sync since `didDecodeRestorableState`).
    ///
    /// Also applies the correct sidebar state UI (hidden/visible traffic lights
    /// and toolbar items) since the observers are skipped during restoration.
    func finalizeInitialization() {
        if let spaceID = windowState.activeSpaceID,
           let space = tabManager.state.space(for: spaceID) {
            tabManager.initializeWindow(windowState, with: space)
        } else {
            tabManager.initializeWindow(windowState)
        }

        if let saved = restoredReadingState {
            restoredReadingState = nil
            if let tab = windowState.restoreReadingState(saved) {
                tabManager.setActiveTab(tab, in: windowState)
            }
        }

        updateWindowBackground()

        DispatchQueue.main.async { [weak self] in
            self?.applySidebarStateUI()
        }
    }

    /// Applies the correct UI state based on current sidebar collapse state.
    ///
    /// This is called after restoration to set up traffic lights, toolbar items,
    /// and tracking regions based on whether the sidebar is collapsed or expanded.
    func applySidebarStateUI() {
        let sidebarItem = splitViewController.splitViewItems[0]

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0

        if sidebarItem.isCollapsed {
            enterCollapsedSidebarState(animated: false)
        } else {
            enterExpandedSidebarState(animated: false)
        }

        NSAnimationContext.endGrouping()
    }
}

// MARK: - NSWindowDelegate Fullscreen

extension RefraxWindowController {
    func windowDidEnterFullScreen(_: Notification) {
        isInFullscreen = true
        captureTrafficLightOrigins(force: true)
        hideSidebarTitlebarBackground()
        // AppKit shows the traffic lights in its own fullscreen titlebar; drop Refrax's
        // compact platter so it does not linger empty at the top of the dock.
        exitCompactTrafficLightMode(animated: false)
        if windowState.usesFloatingTabs {
            applyTrafficLightVisibility(1, animated: false)
        }
        startFullscreenRevealObserving()
    }

    /// Disables the opaque white backstop that AppKit shows behind the sidebar in fullscreen.
    ///
    /// In fullscreen mode with a sidebar split view, `NSToolbarFullScreenContentView` creates
    /// an opaque white layer (`opaqueBackstopLayer`) behind the titlebar. Setting
    /// `needsOpaqueBackstop = NO` disables this, allowing our transparent titlebar to work.
    private func hideSidebarTitlebarBackground() {
        guard let titlebarView,
              let fullScreenContentView = titlebarView.superview?.superview
        else { return }

        let selector = NSSelectorFromString("setNeedsOpaqueBackstop:")
        if fullScreenContentView.responds(to: selector) {
            fullScreenContentView.perform(selector, with: false)
        }
    }

    func windowDidExitFullScreen(_: Notification) {
        isInFullscreen = false
        stopFullscreenRevealObserving()

        captureTrafficLightOrigins(force: true)

        if windowState.usesFloatingTabs {
            applyFloatingTabsChrome()
            return
        }
        let sidebarItem = splitViewController.splitViewItems[0]
        if sidebarItem.isCollapsed {
            if windowState.effectiveSidebarMode == .compact {
                // Restore the compact platter suppressed on entering fullscreen.
                enterCompactTrafficLightMode(animated: false)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.animateWindowChromeEased(forOverlayProgress: 0.0)
                }
            }
        } else {
            updateTrafficLightsForExpandedSidebar(animated: false)
        }
    }
}
