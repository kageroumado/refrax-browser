import AppKit

// MARK: - NSToolbarDelegate

extension RefraxWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            .toggleSidebar,
            .toggleLayoutMode,
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
        case .toggleSidebar:
            return nil

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

        case .toggleLayoutMode:
            let item = NSToolbarItem(itemIdentifier: .toggleLayoutMode)
            item.label = "Layout"
            item.paletteLabel = "Layout Mode"
            item.toolTip = "Enable Layout Mode"
            item.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil)
            item.action = #selector(toggleLayoutMode(_:))
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
            item.setValue(adapter, forKey: "_partitionAdapter")
        }
    }

    @objc
    private func toggleInspectorAction(_: Any?) {
        toggleInspector()
    }

    @objc
    func toggleLayoutMode(_: Any?) {
        if windowState.isInLayoutMode {
            windowState.exitLayoutMode()
        } else {
            windowState.enterLayoutMode()
        }
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
    static let toggleInspector = NSToolbarItem.Identifier("ToggleInspector")
    static let toggleLayoutMode = NSToolbarItem.Identifier("ToggleLayoutMode")
}

extension NSToolbar {
    static let mainIdentifier: NSToolbar.Identifier = "RefraxToolbar"
}
