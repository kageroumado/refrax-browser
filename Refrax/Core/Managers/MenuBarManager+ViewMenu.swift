import AppKit

// MARK: - View Menu

extension MenuBarManager {
    func createViewMenu() -> NSMenuItem {
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")

        // Show/Hide Sidebar
        let sidebarItem = NSMenuItem(
            title: "Toggle Sidebar",
            action: #selector(toggleSidebar(_:)),
            keyEquivalent: "s",
        )
        sidebarItem.keyEquivalentModifierMask = [.command]
        sidebarItem.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
        sidebarItem.target = self
        viewMenu.addItem(sidebarItem)

        // Show/Hide Reference Pane (right sidebar)
        let inspectorItem = NSMenuItem(
            title: "Toggle Reference Pane",
            action: #selector(toggleInspector(_:)),
            keyEquivalent: "s",
        )
        inspectorItem.keyEquivalentModifierMask = [.command, .control]
        inspectorItem.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil)
        inspectorItem.target = self
        viewMenu.addItem(inspectorItem)

        // Sidebar Mode submenu
        let sidebarModeItem = NSMenuItem(title: "Sidebar Mode", action: nil, keyEquivalent: "")
        sidebarModeItem.image = NSImage(systemSymbolName: "sidebar.squares.left", accessibilityDescription: nil)
        let sidebarModeMenu = NSMenu(title: "Sidebar Mode")

        let overlayModeItem = NSMenuItem(
            title: "Overlay",
            action: #selector(setSidebarModeOverlay(_:)),
            keyEquivalent: "",
        )
        overlayModeItem.target = self
        overlayModeItem.tag = MenuItemTag.sidebarModeOverlay.rawValue
        sidebarModeMenu.addItem(overlayModeItem)

        let compactModeItem = NSMenuItem(
            title: "Compact",
            action: #selector(setSidebarModeCompact(_:)),
            keyEquivalent: "",
        )
        compactModeItem.target = self
        compactModeItem.tag = MenuItemTag.sidebarModeCompact.rawValue
        sidebarModeMenu.addItem(compactModeItem)

        sidebarModeItem.submenu = sidebarModeMenu
        viewMenu.addItem(sidebarModeItem)

        viewMenu.addItem(.separator())

        // Tab Navigation
        let nextTabItem = NSMenuItem(
            title: "Select Next Tab",
            action: #selector(selectNextTab(_:)),
            keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!),
        )
        nextTabItem.keyEquivalentModifierMask = [.command, .option]
        nextTabItem.image = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)
        nextTabItem.target = self
        viewMenu.addItem(nextTabItem)

        let previousTabItem = NSMenuItem(
            title: "Select Previous Tab",
            action: #selector(selectPreviousTab(_:)),
            keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!),
        )
        previousTabItem.keyEquivalentModifierMask = [.command, .option]
        previousTabItem.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil)
        previousTabItem.target = self
        viewMenu.addItem(previousTabItem)

        viewMenu.addItem(.separator())

        // Stop
        let stopItem = NSMenuItem(
            title: "Stop",
            action: #selector(stopLoading(_:)),
            keyEquivalent: ".",
        )
        stopItem.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        stopItem.target = self
        viewMenu.addItem(stopItem)

        // Reload
        let reloadItem = NSMenuItem(
            title: "Reload Page",
            action: #selector(reloadPage(_:)),
            keyEquivalent: "r",
        )
        reloadItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        reloadItem.target = self
        viewMenu.addItem(reloadItem)

        let reloadFromOriginItem = NSMenuItem(
            title: "Reload Without Cache",
            action: #selector(reloadPageFromOrigin(_:)),
            keyEquivalent: "r",
        )
        reloadFromOriginItem.keyEquivalentModifierMask = [.command, .shift]
        reloadFromOriginItem.image = NSImage(
            systemSymbolName: "arrow.clockwise.circle",
            accessibilityDescription: nil,
        )
        reloadFromOriginItem.target = self
        viewMenu.addItem(reloadFromOriginItem)

        viewMenu.addItem(.separator())

        // Zoom controls
        let actualSizeItem = NSMenuItem(
            title: "Actual Size",
            action: #selector(actualSize(_:)),
            keyEquivalent: "0",
        )
        actualSizeItem.image = NSImage(systemSymbolName: "textformat.size", accessibilityDescription: nil)
        actualSizeItem.target = self
        viewMenu.addItem(actualSizeItem)

        let zoomInItem = NSMenuItem(
            title: "Zoom In",
            action: #selector(zoomIn(_:)),
            keyEquivalent: "+",
        )
        zoomInItem.image = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: nil)
        zoomInItem.target = self
        viewMenu.addItem(zoomInItem)

        let zoomOutItem = NSMenuItem(
            title: "Zoom Out",
            action: #selector(zoomOut(_:)),
            keyEquivalent: "-",
        )
        zoomOutItem.image = NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: nil)
        zoomOutItem.target = self
        viewMenu.addItem(zoomOutItem)

        viewMenu.addItem(.separator())

        // Downloads panel (unique to View menu)
        let downloadsItem = NSMenuItem(
            title: "Show Downloads",
            action: #selector(showDownloads(_:)),
            keyEquivalent: "l",
        )
        downloadsItem.keyEquivalentModifierMask = [.command, .option]
        downloadsItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        downloadsItem.target = self
        viewMenu.addItem(downloadsItem)

        // Lightboard (Cmd+Shift+L)
        let lightboardItem = NSMenuItem(
            title: "Show Lightboard",
            action: #selector(showLightboard(_:)),
            keyEquivalent: "l",
        )
        lightboardItem.keyEquivalentModifierMask = [.command, .shift]
        lightboardItem.image = NSImage(systemSymbolName: "light.recessed.3", accessibilityDescription: nil)
        lightboardItem.target = self
        viewMenu.addItem(lightboardItem)

        // Passwords window
        let passwordsItem = NSMenuItem(
            title: "Show Passwords",
            action: #selector(showPasswords(_:)),
            keyEquivalent: "p",
        )
        passwordsItem.keyEquivalentModifierMask = [.command, .shift]
        passwordsItem.image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)
        passwordsItem.target = self
        viewMenu.addItem(passwordsItem)

        viewMenu.addItem(.separator())

        // Enter Split View with Command Lens
        let splitViewItem = NSMenuItem(
            title: "Enter Split View",
            action: #selector(enterSplitViewWithLens(_:)),
            keyEquivalent: "t",
        )
        splitViewItem.keyEquivalentModifierMask = [.command, .control]
        splitViewItem.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil)
        splitViewItem.target = self
        viewMenu.addItem(splitViewItem)

        viewMenu.addItem(.separator())

        // Video Viewer (WebKit's in-window viewer for the current video)
        let videoViewerItem = NSMenuItem(
            title: "Toggle Video Viewer",
            action: #selector(toggleVideoViewer(_:)),
            keyEquivalent: "f",
        )
        videoViewerItem.keyEquivalentModifierMask = [.command, .shift]
        videoViewerItem.image = NSImage(systemSymbolName: "play.rectangle", accessibilityDescription: nil)
        videoViewerItem.target = self
        viewMenu.addItem(videoViewerItem)

        // Full Screen
        let fullScreenItem = NSMenuItem(
            title: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f",
        )
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fullScreenItem)

        viewMenuItem.submenu = viewMenu
        return viewMenuItem
    }

    @objc
    func toggleSidebar(_ sender: Any?) {
        activeWindowController?.toggleSidebar(sender)
    }

    @objc
    func toggleInspector(_: Any?) {
        activeWindowController?.toggleInspector()
    }

    @objc
    func selectNextTab(_: Any?) {
        activeWindowController?.selectNextTab()
    }

    @objc
    func selectPreviousTab(_: Any?) {
        activeWindowController?.selectPreviousTab()
    }

    @objc
    func stopLoading(_: Any?) {
        activeWindowController?.stopLoading()
    }

    @objc
    func reloadPage(_: Any?) {
        activeWindowController?.reloadPage()
    }

    @objc
    func reloadPageFromOrigin(_: Any?) {
        activeWindowController?.reloadPageFromOrigin()
    }

    @objc
    func actualSize(_: Any?) {
        guard let controller = activeWindowController,
              let webPage = controller.windowState.activeWebPage else { return }
        webPage.resetZoom()
    }

    @objc
    func zoomIn(_: Any?) {
        guard let controller = activeWindowController,
              let webPage = controller.windowState.activeWebPage else { return }
        webPage.zoomIn()
    }

    @objc
    func zoomOut(_: Any?) {
        guard let controller = activeWindowController,
              let webPage = controller.windowState.activeWebPage else { return }
        webPage.zoomOut()
    }

    @objc
    func toggleVideoViewer(_: Any?) {
        guard let controller = activeWindowController,
              let webPage = controller.windowState.activeWebPage else { return }
        // Needs an active playback session (a video that has started playing);
        // without one the SPI is a silent no-op.
        webPage.toggleInWindowVideo()
    }

    // MARK: - Detail Tray Actions

    @objc
    func showDownloads(_: Any?) {
        activeWindowController?.windowState.toggleDetailTray(.downloads)
    }

    @objc
    func showLightboard(_: Any?) {
        activeWindowController?.windowState.toggleDetailTray(.lightboard)
    }

    // MARK: - Passwords Window

    @objc
    func showPasswords(_: Any?) {
        NSApp.typedDelegate.passwordsWindowController.showWindow()
    }

    // MARK: - Split View Actions

    @objc
    func enterSplitViewWithLens(_: Any?) {
        guard let windowState = activeWindowController?.windowState else { return }

        // Enter layout mode if not already in it
        if !windowState.isInLayoutMode {
            windowState.enterLayoutMode()
        }

        // Set target position to top-right pane and open command lens
        windowState.layoutModeTargetPosition = .topRight
        windowState.openCommandLens()
    }

    // MARK: - Sidebar Mode Actions

    @objc
    func setSidebarModeOverlay(_: Any?) {
        NSApp.typedDelegate.settings.defaultSidebarMode = .overlay
    }

    @objc
    func setSidebarModeCompact(_: Any?) {
        NSApp.typedDelegate.settings.defaultSidebarMode = .compact
    }

    // MARK: - View Menu Validation

    /// Updates sidebar mode menu item checkmarks based on current setting.
    func updateViewMenu(_ menu: NSMenu) {
        guard menu.title == "View" || menu.title == "Sidebar Mode" else { return }

        // Find sidebar mode submenu
        let sidebarModeMenu: NSMenu? = if menu.title == "Sidebar Mode" {
            menu
        } else {
            menu.item(withTitle: "Sidebar Mode")?.submenu
        }

        guard let sidebarModeMenu else { return }

        let currentMode = NSApp.typedDelegate.settings.defaultSidebarMode

        // Update checkmarks
        for item in sidebarModeMenu.items {
            switch item.tag {
            case MenuItemTag.sidebarModeOverlay.rawValue:
                item.state = currentMode == .overlay ? .on : .off
            case MenuItemTag.sidebarModeCompact.rawValue:
                item.state = currentMode == .compact ? .on : .off
            default:
                break
            }
        }
    }
}
