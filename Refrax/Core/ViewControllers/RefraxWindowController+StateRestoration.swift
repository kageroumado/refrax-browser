import AppKit
import SwiftUI

// MARK: - State Restoration

extension RefraxWindowController {
    /// Encode window-specific state for restoration.
    ///
    /// ## What's Encoded (Per-Window)
    ///
    /// - Window frame (origin, size)
    /// - Floating placements and island positions
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
        state.encode(windowState.fileIsland.isCoupled as NSNumber, forKey: "fileIslandCoupled")
        // Encode window frame for explicit restoration.
        // AppKit's default NSWindow.restoreState doesn't reliably restore frame
        // when the window is created with .zero contentRect via NSWindowRestoration.
        if let frame = window?.frame {
            state.encode(frame.origin.x as NSNumber, forKey: "windowFrameX")
            state.encode(frame.origin.y as NSNumber, forKey: "windowFrameY")
            state.encode(frame.size.width as NSNumber, forKey: "windowFrameWidth")
            state.encode(frame.size.height as NSNumber, forKey: "windowFrameHeight")
        }

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
    /// 1. Restore floating placements and island positions
    /// 2. Restore window frame
    /// 3. Restore window background color
    func decodeWindowState(from state: NSCoder) {
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
        if let coupled = state.decodeObject(of: NSNumber.self, forKey: "fileIslandCoupled")?.boolValue {
            windowState.fileIsland.isCoupled = coupled
        }

        if let frameX = state.decodeObject(of: NSNumber.self, forKey: "windowFrameX")?.doubleValue,
           let frameY = state.decodeObject(of: NSNumber.self, forKey: "windowFrameY")?.doubleValue,
           let frameWidth = state.decodeObject(of: NSNumber.self, forKey: "windowFrameWidth")?.doubleValue,
           let frameHeight = state.decodeObject(of: NSNumber.self, forKey: "windowFrameHeight")?.doubleValue {
            applyFrame(NSRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight))
        }

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
        applyFrame(geometry.frame)
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

    /// Completes window initialization after DB restoration.
    ///
    /// Called after `restoreFromPersistence()` to load tabs and reapply colors
    /// (colors may have changed via iCloud sync since `didDecodeRestorableState`),
    /// and hides the standard window buttons the Control Island replaces.
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
        hideStandardWindowButtons()
    }
}

// MARK: - NSWindowDelegate Fullscreen

extension RefraxWindowController {
    func windowDidEnterFullScreen(_: Notification) {
        disableFullscreenTitlebarBackstop()
        hideStandardWindowButtons()
    }

    /// Disables the opaque backstop AppKit draws behind the fullscreen titlebar.
    ///
    /// `NSToolbarFullScreenContentView` adds an opaque layer (`opaqueBackstopLayer`) behind
    /// the titlebar. Setting `needsOpaqueBackstop = NO` keeps the page visible beneath it.
    private func disableFullscreenTitlebarBackstop() {
        guard let titlebarView = (window?.contentView?.superview as? NSThemeFrame)?.titlebarView,
              let fullScreenContentView = titlebarView.superview?.superview
        else { return }

        let selector = NSSelectorFromString("setNeedsOpaqueBackstop:")
        if fullScreenContentView.responds(to: selector) {
            fullScreenContentView.perform(selector, with: false)
        }
    }

    func windowDidExitFullScreen(_: Notification) {
        hideStandardWindowButtons()
    }
}
