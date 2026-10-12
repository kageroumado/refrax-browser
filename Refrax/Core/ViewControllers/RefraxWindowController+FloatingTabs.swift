import AppKit
import SwiftUI

extension RefraxWindowController {
    /// Keeps browser controls reachable above transient lenses and the recent-tab picker.
    func setupControlIslandLayer(contentView: NSView) {
        let controls = FloatingTabsHostingView(rootView: ControlIslandLayer().refraxEnvironment(environment))
        controls.sizingOptions = []
        controls.controlState = { [weak windowState] in windowState?.controlIsland }
        controls.hitRegions = { [weak controls, weak windowState, weak tabCanvasManager] in
            guard tabCanvasManager?.showsFloatingControls == true else { return [] }
            if tabCanvasManager?.regionSelection != nil, let controls { return [controls.bounds] }
            return windowState?.controlIsland.hitRegions ?? []
        }
        contentView.addSubview(controls)
        controls.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            controls.topAnchor.constraint(equalTo: contentView.topAnchor),
            controls.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    /// Gives the page the full window and keeps spatial tabs available above it.
    func useFloatingTabs() {
        windowState.usesFloatingTabs = true
        let sidebar = splitViewController.splitViewItems[0]
        sidebar.isCollapsed = true
        windowState.isSidebarCollapsed = true
        applyFloatingTabsChrome()
    }

    func applyFloatingTabsChrome() {
        overlayAnimationGeneration &+= 1
        cancelTutorialPeek()
        hideTask?.cancel()
        hideTask = nil
        sidebarExpansionTask?.cancel()
        sidebarExpansionTask = nil
        removeOverlayAnimations()
        isAnimatingToVisible = false
        isOverlayTriggered = false
        sidebarTrackingView?.isOverlayTriggered = false
        trackingViewWidthConstraint?.constant = 0
        updateTrackingAreaImmediately()
        hideSidebarOverlayInstantly()
        exitCompactTrafficLightMode(animated: false)
        cancelChromeAnimations()
        hideToolbarItemsInstantly()
        window?.toolbar?.isVisible = false
        applyTrafficLightVisibility(1, animated: false)
        setDetailTrayToOverlayProgressInstantly(0)
        hideEdgeExtensionBackground(animated: false)
    }
}
