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
    /// - Inspector: collapsed state, docked width
    /// - Active space ID
    /// - Window background color and mix settings
    ///
    /// ## What's NOT Encoded Here
    ///
    /// - Reference tabs → Per-space in SwiftData
    func encodeWindowState(to state: NSCoder) {
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

        let inspectorItem = splitViewController.splitViewItems[2]
        state.encode(inspectorItem.isCollapsed as NSNumber, forKey: "inspectorCollapsed")

        let inspectorWidth = inspectorItem.isCollapsed ? windowState.referencePaneDockedWidth : inspectorItem.viewController.view.frame.width
        state.encode(inspectorWidth as NSNumber, forKey: "referencePaneDockedWidth")

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
    /// 3. Restore inspector (docked width, collapsed state)
    /// 4. Restore window background color
    func decodeWindowState(from state: NSCoder) {
        isRestoringState = true
        defer { isRestoringState = false }

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

        let dockedWidth = state.decodeObject(of: NSNumber.self, forKey: "referencePaneDockedWidth")?.doubleValue
            ?? Constants.Layout.inspectorDefaultWidth
        let inspectorCollapsed = state.decodeObject(of: NSNumber.self, forKey: "inspectorCollapsed")?.boolValue ?? true

        applyChrome(
            sidebarWidth: sidebarWidth,
            sidebarCollapsed: sidebarCollapsed,
            inspectorWidth: dockedWidth,
            inspectorCollapsed: inspectorCollapsed,
        )

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
    /// The inspector always starts collapsed in new windows; its width is
    /// still applied so it opens at the last-used size. Must be called
    /// before `showWindow(_:)` so the window appears at its final frame.
    func applyInitialGeometry(_ geometry: SavedWindowGeometry) {
        isRestoringState = true
        defer { isRestoringState = false }

        applyFrame(geometry.frame)

        let sidebarWidth = geometry.sidebarWidth.clamped(
            to: Constants.Layout.sidebarMinWidth ... Constants.Layout.sidebarMaxWidth,
        )
        let inspectorWidth = geometry.inspectorWidth.clamped(
            to: Constants.Layout.inspectorMinWidth ... Constants.Layout.inspectorMaxWidth,
        )

        applyChrome(
            sidebarWidth: sidebarWidth,
            sidebarCollapsed: geometry.isSidebarCollapsed,
            inspectorWidth: inspectorWidth,
            inspectorCollapsed: true,
        )
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

    /// Applies sidebar and inspector dimensions and collapse state, syncing
    /// split view positions, `WindowState`, and the overlay width constraint,
    /// then applies the matching sidebar UI (traffic lights, toolbar items)
    /// before the window becomes visible to prevent a flash of incorrect state.
    private func applyChrome(
        sidebarWidth: CGFloat,
        sidebarCollapsed: Bool,
        inspectorWidth: CGFloat,
        inspectorCollapsed: Bool,
    ) {
        let sidebarItem = splitViewController.splitViewItems[0]
        let inspectorItem = splitViewController.splitViewItems[2]

        lastCollapsedThickness = sidebarWidth
        windowState.sidebarThickness = sidebarWidth

        // Container width = sidebarWidth + padding (see setupSidebarOverlayContainer docs)
        let padding = Constants.SidebarAnimation.glassEffectPadding
        sidebarOverlayWidthConstraint?.constant = sidebarWidth + padding

        sidebarItem.isCollapsed = sidebarCollapsed
        windowState.isSidebarCollapsed = sidebarCollapsed

        if !sidebarCollapsed {
            splitViewController.splitView.setPosition(sidebarWidth, ofDividerAt: 0)
        }

        windowState.referencePaneDockedWidth = inspectorWidth

        splitViewController.splitView.setPosition(
            splitViewController.view.bounds.width - inspectorWidth,
            ofDividerAt: 1,
        )

        inspectorItem.isCollapsed = inspectorCollapsed
        windowState.isInspectorCollapsed = inspectorCollapsed

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

        captureTrafficLightOrigins(force: true)

        let sidebarItem = splitViewController.splitViewItems[0]
        if sidebarItem.isCollapsed {
            DispatchQueue.main.async { [weak self] in
                self?.animateWindowChromeEased(forOverlayProgress: 0.0)
            }
        } else {
            updateTrafficLightsForExpandedSidebar(animated: false)
        }
    }
}
