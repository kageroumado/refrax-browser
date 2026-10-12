import AppKit

// MARK: - NSToolbarDelegate

extension RefraxWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            .toggleSidebarGrouped,
            .toggleFloatingTabs,
            .toggleTabCanvas,
            .toggleInspector,
            .sidebarTrackingSeparator,
            .flexibleSpace,
        ]
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier id: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool,
    ) -> NSToolbarItem? {
        switch id {
        case .toggleSidebarGrouped:
            // AppKit draws anything under the .toggleSidebar identifier on a glass
            // platter of its own, even a plain bordered item. Under a custom
            // identifier the same item shares its neighbors' platter.
            let item = NSToolbarItem(itemIdentifier: .toggleSidebarGrouped)
            item.label = "Sidebar"
            item.paletteLabel = "Toggle Sidebar"
            item.toolTip = "Hide or Show Sidebar"
            item.image = NSImage(systemSymbolName: "sidebar.leading", accessibilityDescription: nil)
            item.action = #selector(toggleSidebar(_:))
            item.target = self
            item.isBordered = true
            configureSidebarTracking(for: item)
            return item

        case .toggleInspector:
            let item = NSToolbarItem(itemIdentifier: .toggleInspector)
            item.label = "Reference"
            item.paletteLabel = "Reference Pane"
            item.toolTip = "Show Reference Pane"
            item.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil)
            item.action = #selector(toggleInspectorAction(_:))
            item.target = self
            item.isBordered = true
            configureSidebarTracking(for: item)
            return item

        case .toggleFloatingTabs:
            let item = NSToolbarItem(itemIdentifier: .toggleFloatingTabs)
            item.label = "Floating Tabs"
            item.paletteLabel = "Floating Tabs"
            item.toolTip = "Show Floating Tabs · Hold Control to peek"
            item.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: nil)
            item.action = #selector(toggleFloatingTabs(_:))
            item.target = self
            item.isBordered = true
            configureSidebarTracking(for: item)
            return item

        case .toggleTabCanvas:
            let item = NSToolbarItem(itemIdentifier: .toggleTabCanvas)
            item.label = "Canvas"
            item.paletteLabel = "Tab Canvas"
            item.toolTip = "Show All Tabs on the Canvas (⌘⇧\\)"
            item.image = NSImage(systemSymbolName: TabCanvasManager.symbolName, accessibilityDescription: nil)
            item.action = #selector(toggleTabCanvas(_:))
            item.target = self
            item.isBordered = true
            configureSidebarTracking(for: item)
            return item

        default:
            return nil
        }
    }

    func configureSidebarTracking(for item: NSToolbarItem) {
        item.trackedSplitView = splitViewController.splitView
        item.trackedSplitViewDividerIndex = 0
        if let adapter = splitViewSidebarTrackingAdapter {
            item._setPartitionAdapter(adapter)
        }
    }

    @objc
    private func toggleInspectorAction(_: Any?) {
        toggleInspector()
    }

    @objc
    func toggleFloatingTabs(_: Any?) {
        tabCanvasManager.toggleFloatingTabs()
    }

    @objc
    func toggleTabCanvas(_: Any?) {
        tabCanvasManager.toggle()
    }
}

// MARK: - Sidebar Tracking Adapters

extension RefraxWindowController {
    /// Configures the sidebar tracking adapters used to align the titlebar and toolbar.
    ///
    /// Uses `OverlaySidebarTrackingAdapter` which wraps `_NSSplitViewPartitionAdapter`.
    /// This gives us a single adapter that:
    /// - Fully implements `NSSidebarTrackingAdapter` (including `isCollapsed`)
    /// - Can override `sidebarDividerPosition` for overlay mode
    func setupSidebarTrackingAdapters() {
        let adapter = OverlaySidebarTrackingAdapter(splitView: splitViewController.splitView)
        splitViewSidebarTrackingAdapter = adapter

        applySidebarTrackingAdapter(adapter)
        applyPartitionAdapterToSeparator(adapter)
    }

    /// Applies the given tracking adapter to the theme frame.
    func applySidebarTrackingAdapter(_ adapter: NSObject?) {
        themeFrame?.sidebarTrackingAdapter = adapter as? any NSObject & NSSidebarTrackingAdapter
    }

    /// Updates the sidebar divider position for the overlay mode.
    ///
    /// Sets `overrideDividerPosition` on our `OverlaySidebarTrackingAdapter` so that
    /// both the theme frame and toolbar separator see the overlay position.
    ///
    /// Skips the toolbar relayout if the position hasn't actually changed, to prevent
    /// transforms from being reset during animation.
    func updateOverlaySidebarTracking(progress: CGFloat) {
        guard let adapter = splitViewSidebarTrackingAdapter else { return }

        let dividerPosition = overlayDividerPosition(progress: progress)

        let previousPosition = adapter.overrideDividerPosition ?? 0
        guard abs(dividerPosition - previousPosition) > 0.1 else { return }

        adapter.overrideDividerPosition = dividerPosition
        updateSidebarDividerPosition(dividerPosition)
    }

    /// Restores split view tracking when the real sidebar is visible.
    ///
    /// Clears the `overrideDividerPosition` so the adapter returns the real
    /// split view position again.
    func restoreSplitViewSidebarTracking() {
        guard let adapter = splitViewSidebarTrackingAdapter else { return }

        adapter.overrideDividerPosition = nil
        lastToolbarDividerPosition = nil

        let dividerPosition = adapter.sidebarDividerPosition

        updateSidebarDividerPosition(dividerPosition)
    }

    /// Sets the partition adapter on the sidebar tracking separator item.
    func applyPartitionAdapterToSeparator(_ adapter: NSObject?) {
        sidebarTrackingSeparatorItem?._setPartitionAdapter(adapter as? any NSSidebarTrackingAdapter)
    }

    func overlayDividerPosition(progress: CGFloat) -> CGFloat {
        let sidebarWidth = windowState.sidebarThickness + sidebarDividerOffset
        return sidebarWidth * progress
    }

    /// Updates the toolbar's sidebar divider position.
    ///
    /// This controls where the sidebar tracking separator appears in the toolbar.
    /// The divider position determines how toolbar items are partitioned between
    /// the sidebar area and the main content area.
    func updateSidebarDividerPosition(_ position: CGFloat) {
        guard let toolbarView else { return }

        if let lastPosition = lastToolbarDividerPosition,
           abs(position - lastPosition) < 0.1 {
            return
        }
        lastToolbarDividerPosition = position

        toolbarView.sidebarDividerPosition = position
        toolbarView._layoutDirtyItemViewersAndTileToolbar()
    }
}

// MARK: - Toolbar Item Identifiers

extension NSToolbarItem.Identifier {
    /// The sidebar toggle under an identifier AppKit does not single out; see the delegate.
    static let toggleSidebarGrouped = NSToolbarItem.Identifier("ToggleSidebar")
    static let toggleInspector = NSToolbarItem.Identifier("ToggleInspector")
    static let toggleFloatingTabs = NSToolbarItem.Identifier("ToggleFloatingTabs")
    static let toggleTabCanvas = NSToolbarItem.Identifier("ToggleTabCanvas")
}

extension NSToolbar {
    static let mainIdentifier: NSToolbar.Identifier = "RefraxToolbar"
}
