import AppKit

// MARK: - View Menu

extension MenuBarManager {
    func createViewMenu() -> NSMenuItem {
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        // updateViewMenu keeps the engine, favorite, and mute items' titles current.
        viewMenu.delegate = self

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

        // The title tracks the active page's engine; see updateViewMenu.
        let switchEngineItem = NSMenuItem(
            title: "Reload in Chromium",
            action: #selector(switchRenderingEngine(_:)),
            keyEquivalent: "r",
        )
        switchEngineItem.keyEquivalentModifierMask = [.command, .option, .control]
        switchEngineItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        switchEngineItem.tag = MenuItemTag.switchRenderingEngine.rawValue
        switchEngineItem.target = self
        viewMenu.addItem(switchEngineItem)

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
            title: "Show Tab Statistics",
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

        // Local Devices window
        let localDevicesItem = NSMenuItem(
            title: "Local Devices",
            action: #selector(showLocalDevices(_:)),
            keyEquivalent: "",
        )
        localDevicesItem.image = NSImage(systemSymbolName: "network", accessibilityDescription: nil)
        localDevicesItem.target = self
        viewMenu.addItem(localDevicesItem)

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

        let floatingItem = NSMenuItem(title: "Floating Tabs", action: #selector(toggleFloatingTabs(_:)), keyEquivalent: "")
        floatingItem.target = self
        viewMenu.addItem(floatingItem)
        let currentTabItem = NSMenuItem(title: "Current Tab…", action: #selector(showCurrentTabInfo(_:)), keyEquivalent: "")
        currentTabItem.target = self
        viewMenu.addItem(currentTabItem)
        let returnItem = NSMenuItem(title: "Return to Activity", action: #selector(returnToActivity(_:)), keyEquivalent: "")
        returnItem.target = self
        viewMenu.addItem(returnItem)
        let keepItem = NSMenuItem(title: "Keep Part Visible…", action: #selector(keepCurrentRegion(_:)), keyEquivalent: "")
        keepItem.target = self
        viewMenu.addItem(keepItem)
        for edge in FloatingDockEdge.allCases {
            let key = TabActions.dockKey(edge)
            let dockItem = NSMenuItem(
                title: "Dock Current Page \(edge.title)",
                action: edge == .leading ? #selector(dockCurrentPageLeft(_:)) : #selector(dockCurrentPageRight(_:)),
                keyEquivalent: String(key.character),
            )
            dockItem.keyEquivalentModifierMask = key.modifiers
            dockItem.image = NSImage(systemSymbolName: edge == .leading ? "rectangle.lefthalf.inset.filled" : "rectangle.righthalf.inset.filled", accessibilityDescription: nil)
            dockItem.target = self
            viewMenu.addItem(dockItem)
        }
        viewMenu.addItem(createTableMenuItem())
        let favoriteItem = NSMenuItem(title: "Favorite Current Page", action: #selector(favoriteCurrentPage(_:)), keyEquivalent: "")
        favoriteItem.target = self
        favoriteItem.tag = MenuItemTag.favoriteCurrentPage.rawValue
        viewMenu.addItem(favoriteItem)
        let favoritesDrawerItem = NSMenuItem(title: "Show Favorites", action: #selector(showFavoritesDrawer(_:)), keyEquivalent: "")
        favoritesDrawerItem.image = NSImage(systemSymbolName: "star", accessibilityDescription: nil)
        favoritesDrawerItem.target = self
        viewMenu.addItem(favoritesDrawerItem)
        // The title tracks Hide at the Edge; see updateViewMenu.
        let edgeHidingItem = NSMenuItem(
            title: "Hide Browser Controls",
            action: #selector(toggleBrowserControlsEdgeHiding(_:)),
            keyEquivalent: "s",
        )
        edgeHidingItem.keyEquivalentModifierMask = [.command]
        edgeHidingItem.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
        edgeHidingItem.toolTip = "The controls and the File Island slide past the window's edge; the pointer coming to that edge brings them back"
        edgeHidingItem.tag = MenuItemTag.browserControlsEdgeHiding.rawValue
        edgeHidingItem.target = self
        viewMenu.addItem(edgeHidingItem)
        let controlsItem = NSMenuItem(title: "Focus Browser Controls", action: #selector(focusBrowserControls(_:)), keyEquivalent: "")
        controlsItem.target = self
        viewMenu.addItem(controlsItem)
        let customizeControlsItem = NSMenuItem(title: "Customize Control Island…", action: #selector(customizeControls(_:)), keyEquivalent: "")
        customizeControlsItem.target = self
        viewMenu.addItem(customizeControlsItem)
        let resetControlsItem = NSMenuItem(title: "Reset Control Position", action: #selector(resetControlPosition(_:)), keyEquivalent: "")
        resetControlsItem.target = self
        viewMenu.addItem(resetControlsItem)

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

        let muteItem = NSMenuItem(title: "Mute Tab", action: #selector(toggleMuteCurrentTab(_:)), keyEquivalent: "m")
        muteItem.keyEquivalentModifierMask = [.control]
        muteItem.image = NSImage(systemSymbolName: "speaker.slash", accessibilityDescription: nil)
        muteItem.tag = MenuItemTag.muteTab.rawValue
        muteItem.target = self
        viewMenu.addItem(muteItem)

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

    /// Reloads the active page in the other rendering engine: system WebKit ⇄ the first installed engine.
    @objc
    func switchRenderingEngine(_: Any?) {
        guard let page = activeWindowController?.windowState.focusedWebPage else { return }
        let registry = NSApp.typedDelegate.engineRegistry
        guard let target = alternateEngine(for: page, in: registry) else { return }
        page.reload(in: target, registry: registry)
    }

    /// The engine the switch command moves `page` to.
    private func alternateEngine(for page: WebPage?, in registry: EngineRegistry) -> EngineDescriptor? {
        if let page, page.activeEngineID != .systemWebKit {
            return EngineRegistry.systemWebKit
        }
        return registry.descriptors.first { $0.id != .systemWebKit }
    }

    @objc
    func actualSize(_: Any?) {
        guard let controller = activeWindowController,
              let webPage = controller.windowState.focusedWebPage else { return }
        webPage.resetZoom()
    }

    @objc
    func zoomIn(_: Any?) {
        guard let controller = activeWindowController,
              let webPage = controller.windowState.focusedWebPage else { return }
        webPage.zoomIn()
    }

    @objc
    func zoomOut(_: Any?) {
        guard let controller = activeWindowController,
              let webPage = controller.windowState.focusedWebPage else { return }
        webPage.zoomOut()
    }

    @objc
    func toggleVideoViewer(_: Any?) {
        guard let controller = activeWindowController,
              let webPage = controller.windowState.focusedWebPage else { return }
        // Needs an active playback session (a video that has started playing);
        // without one the SPI is a silent no-op.
        webPage.toggleInWindowVideo()
    }

    /// Mutes the current tab, or unmutes it when it is muted.
    @objc
    func toggleMuteCurrentTab(_: Any?) {
        guard let controller = activeWindowController, let tab = controller.windowState.activeTab else { return }
        TabMediaControl(tab: tab, pagePool: controller.tabManager.pagePool).toggleMute()
    }

    // MARK: - Detail Tray Actions

    @objc
    func showDownloads(_: Any?) {
        activeWindowController?.showDownloads()
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

    // MARK: - Local Devices Window

    @objc
    func showLocalDevices(_: Any?) {
        NSApp.typedDelegate.localDevicesWindowController.showWindow()
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

    @objc
    func toggleFloatingTabs(_: Any?) {
        activeWindowController?.tabCanvasManager.toggleFloatingTabs()
    }

    @objc
    func focusBrowserControls(_: Any?) {
        activeWindowController?.windowState.controlIsland.focus()
    }

    @objc
    func toggleBrowserControlsEdgeHiding(_: Any?) {
        guard let windowState = activeWindowController?.windowState else { return }
        windowState.controlIsland.toggleEdgeHiding(with: windowState.fileIsland)
    }

    @objc
    func showCurrentTabInfo(_: Any?) {
        activeWindowController?.windowState.controlIsland.tabInfo.show()
    }

    @objc
    func resetControlPosition(_: Any?) {
        activeWindowController?.windowState.controlIsland.resetPlacement()
    }

    @objc
    func customizeControls(_: Any?) {
        activeWindowController?.windowState.controlIsland.showsCustomization = true
    }

    @objc
    func returnToActivity(_: Any?) {
        guard let controller = activeWindowController else { return }
        controller.tabManager.returnFromLook(in: controller.windowState)
    }

    @objc
    func keepCurrentRegion(_: Any?) {
        guard let controller = activeWindowController, let tab = controller.windowState.focusedPage?.tab else { return }
        controller.tabCanvasManager.beginRegionSelection(for: tab)
    }

    @objc
    func dockCurrentPageLeft(_: Any?) {
        activeWindowController?.tabCanvasManager.dockCurrentPage(to: .leading)
    }

    @objc
    func dockCurrentPageRight(_: Any?) {
        activeWindowController?.tabCanvasManager.dockCurrentPage(to: .trailing)
    }

    @objc
    func favoriteCurrentPage(_: Any?) {
        guard let controller = activeWindowController, let tab = controller.windowState.focusedPage?.tab,
              let bookmarks = controller.tabManager.bookmarksManager else { return }
        ControlIslandTabActions(tab: tab, windowState: controller.windowState, tabs: controller.tabManager, bookmarks: bookmarks).toggleFavorite()
    }

    @objc
    func showFavoritesDrawer(_: Any?) {
        activeWindowController?.windowState.toggleDetailTray(.favorites)
    }

    // MARK: - View Menu Validation

    /// Updates the engine, favorite, mute, and browser controls items for the focused page.
    func updateViewMenu(_ menu: NSMenu) {
        guard menu.title == "View" else { return }

        if let engineItem = menu.item(withTag: MenuItemTag.switchRenderingEngine.rawValue) {
            let page = activeWindowController?.windowState.focusedWebPage
            let target = alternateEngine(for: page, in: NSApp.typedDelegate.engineRegistry)
            engineItem.title = "Reload in \(target?.displayName ?? "Another Engine")"
            engineItem.isHidden = target == nil
        }

        if let favoriteItem = menu.item(withTag: MenuItemTag.favoriteCurrentPage.rawValue) {
            let isFavorite = activeWindowController?.windowState.focusedPage?.tab?.isFavorite == true
            favoriteItem.title = isFavorite ? "Remove from Favorites" : "Favorite Current Page"
            favoriteItem.image = NSImage(systemSymbolName: isFavorite ? "star.slash" : "star", accessibilityDescription: nil)
        }

        if let edgeHidingItem = menu.item(withTag: MenuItemTag.browserControlsEdgeHiding.rawValue) {
            let hides = activeWindowController?.windowState.controlIsland.configuration.hidesAtEdge == true
            edgeHidingItem.title = hides ? "Show Browser Controls" : "Hide Browser Controls"
        }

        if let muteItem = menu.item(withTag: MenuItemTag.muteTab.rawValue) {
            let isMuted = activeWindowController.flatMap { controller in
                controller.windowState.activeTab.map { TabMediaControl(tab: $0, pagePool: controller.tabManager.pagePool).isMuted }
            } ?? false
            muteItem.title = isMuted ? "Unmute Tab" : "Mute Tab"
            muteItem.image = NSImage(systemSymbolName: isMuted ? "speaker.wave.2" : "speaker.slash", accessibilityDescription: nil)
        }
    }
}
