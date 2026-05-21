import AppKit

extension Sidebar {
    /// Handles middle-click events for the entire sidebar using a single event monitor.
    ///
    /// Instead of per-tab NSViewRepresentables (each with its own event monitor), this
    /// coordinator maintains one event monitor and looks up which tab was clicked via
    /// LayoutManager frames. This eliminates O(n) monitor overhead where n = tab count.
    ///
    /// ## Performance
    ///
    /// With N tabs, the previous approach created:
    /// - N NSViews managed by SwiftUI
    /// - N event monitors all firing on every middle click
    /// - N `updateNSView` calls on every parent re-render
    ///
    /// This approach creates:
    /// - 1 event monitor
    /// - O(n) frame lookup on click (acceptable—clicks are rare)
    /// - Zero SwiftUI overhead
    @Observable
    final class MiddleClickCoordinator {
        // MARK: - Dependencies

        unowned var layoutManager: LayoutManager!
        unowned var tabManager: TabManager!
        unowned var windowState: WindowState!
        unowned var state: Sidebar.GeometryState!

        // MARK: - Private State

        @ObservationIgnored
        private var eventMonitor: Any?

        // MARK: - Lifecycle

        /// Sets up the event monitor. Call once when sidebar appears.
        func setup() {
            setupEventMonitor()
        }

        /// Tears down the event monitor. Call when sidebar disappears.
        func teardown() {
            removeEventMonitor()
        }

        // MARK: - Private Methods

        private func setupEventMonitor() {
            guard eventMonitor == nil else { return }

            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
                self?.handleMiddleClick(event)
                return event
            }
        }

        private func removeEventMonitor() {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }

        private func handleMiddleClick(_ event: NSEvent) {
            // Only handle middle mouse button (button 2)
            guard event.buttonNumber == 2 else { return }

            // Only handle clicks in our window
            guard let sidebarWindow = windowState.window,
                  event.window === sidebarWindow
            else { return }

            // Convert from AppKit coordinates (origin bottom-left) to SwiftUI coordinates (origin top-left)
            // Use contentView bounds, not contentLayoutRect, because with fullSizeContentView
            // the event coordinates are relative to the full content view (including under toolbar)
            guard let contentViewHeight = sidebarWindow.contentView?.bounds.height else { return }
            let locationInWindow = CGPoint(
                x: event.locationInWindow.x,
                y: contentViewHeight - event.locationInWindow.y,
            )

            // Find the item whose computed frame contains this point
            for itemID in layoutManager.metadata.keys {
                guard let frame = state.itemFrame(for: itemID) else { continue }

                if frame.contains(locationInWindow) {
                    // Found the clicked item - check if it's a tab in the active space
                    if let tab = windowState.activeSpace?.tabs.first(where: { $0.id == itemID }) {
                        tabManager.requestCloseTab(tab)
                    }
                    return
                }
            }
        }
    }
}
