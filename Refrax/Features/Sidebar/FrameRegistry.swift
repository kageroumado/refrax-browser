import AppKit
import SwiftUI

/// Registry holding references to item frame observer views.
///
/// Provides direct access to NSView frames without SwiftUI geometry/preference overhead.
/// Computes visible items by checking which registered view frames intersect the viewport.
extension Sidebar {
    @Observable
    final class FrameRegistry {
        /// Registered views keyed by item ID.
        private var views: [UUID: NSView] = [:]

        /// Current visible viewport in window coordinates.
        ///
        /// Updated by Sidebar when scroll offset or size changes.
        var viewport: CGRect = .zero {
            didSet {
                if viewport != oldValue {
                    recomputeVisibleItems()
                }
            }
        }

        /// Currently visible item IDs (views whose frames intersect the viewport).
        ///
        /// Observable so Sidebar can react to visibility changes.
        private(set) var visibleItemIDs: Set<UUID> = []

        // MARK: - Section Frame Views

        /// NSView for the sidebar container (for bounds calculation).
        weak var sidebarView: NSView?

        /// NSView for the favorites grid section.
        weak var favoritesGridView: NSView?

        /// LayoutManager reference for accessing section item IDs.
        weak var layoutManager: Sidebar.LayoutManager?

        /// Sidebar bounds in window coordinates.
        var sidebarBounds: CGRect {
            guard let view = sidebarView else { return .zero }
            return view.convert(view.bounds, to: nil)
        }

        /// Favorites grid frame in window coordinates.
        var favoritesGridFrame: CGRect {
            guard let view = favoritesGridView else { return .zero }
            return view.convert(view.bounds, to: nil)
        }

        func register(_ view: NSView, for id: UUID) {
            views[id] = view
        }

        func unregister(id: UUID) {
            views.removeValue(forKey: id)
            #if DEBUG
                testFrames.removeValue(forKey: id)
            #endif
        }

        /// Gets the frame of an item in window coordinates.
        func frame(for id: UUID) -> CGRect? {
            #if DEBUG
                // In tests, check if we have a test frame entry for this ID.
                // The entry can be: present with a frame, present with nil (no frame), or absent.
                if let entry = testFrames[id] {
                    // Entry exists - return the frame (or nil if explicitly set to nil)
                    return entry
                }
            #endif
            guard let view = views[id] else { return nil }
            return view.convert(view.bounds, to: nil)
        }

        // MARK: - Testing Support

        #if DEBUG
            /// Mock frames for testing (bypasses NSView lookup).
            /// Use `nil` value to indicate "no frame" (simulates item scrolled offscreen).
            private var testFrames: [UUID: CGRect?] = [:]

            /// Sets a mock frame for testing purposes.
            /// Pass `nil` to simulate an item without a frame (scrolled offscreen).
            func setTestFrame(_ frame: CGRect?, for id: UUID) {
                testFrames[id] = frame
            }

            /// Removes a test frame entry entirely (different from setting to nil).
            func removeTestFrame(for id: UUID) {
                testFrames.removeValue(forKey: id)
            }

            /// Clears all mock test frames.
            func clearTestFrames() {
                testFrames.removeAll()
            }
        #endif

        /// Recomputes which items are visible based on current viewport.
        ///
        /// Uses raw NSView frames (without gesture offset) since the viewport
        /// is captured via SwiftUI geometry which matches NSView coordinates.
        func recomputeVisibleItems() {
            guard !viewport.isEmpty else {
                visibleItemIDs = []
                return
            }

            var visible: Set<UUID> = []
            for (id, view) in views {
                let frame = view.convert(view.bounds, to: nil)
                if viewport.intersects(frame) {
                    visible.insert(id)
                }
            }
            visibleItemIDs = visible
        }
    }
}

// MARK: - SwiftUI View

/// Invisible view that registers its underlying NSView for frame tracking.
///
/// Add this as an overlay or background to any view that needs frame tracking.
/// The NSView reference is automatically managed (registered on appear, unregistered on disappear).
struct ItemFrameObserver: NSViewRepresentable {
    let id: UUID
    @Environment(Sidebar.FrameRegistry.self) private var registry

    func makeNSView(context _: Context) -> FrameObserverNSView {
        let view = FrameObserverNSView()
        view.itemID = id
        view.registry = registry
        return view
    }

    func updateNSView(_ nsView: FrameObserverNSView, context _: Context) {
        // ID shouldn't change, but handle it if it does
        if nsView.itemID != id {
            if let oldID = nsView.itemID {
                registry.unregister(id: oldID)
            }
            nsView.itemID = id
            registry.register(nsView, for: id)
        }
    }
}

/// The underlying NSView that gets registered with the frame registry.
final class FrameObserverNSView: NSView {
    var itemID: UUID?
    weak var registry: Sidebar.FrameRegistry?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, let id = itemID {
            registry?.register(self, for: id)
        } else if let id = itemID {
            registry?.unregister(id: id)
        }
    }

    override func removeFromSuperview() {
        if let id = itemID {
            registry?.unregister(id: id)
        }
        super.removeFromSuperview()
    }

    override var isFlipped: Bool { true }
}

// MARK: - Section Frame Observers

/// Identifies which section an observer is tracking.
enum SectionFrameType {
    case sidebar
    case favoritesGrid
}

/// Invisible view that registers its underlying NSView for section frame tracking.
struct SectionFrameObserver: NSViewRepresentable {
    let section: SectionFrameType
    @Environment(Sidebar.FrameRegistry.self) private var registry

    func makeNSView(context _: Context) -> SectionFrameNSView {
        let view = SectionFrameNSView()
        view.section = section
        view.registry = registry
        return view
    }

    func updateNSView(_ nsView: SectionFrameNSView, context _: Context) {
        nsView.section = section
        nsView.registry = registry
    }
}

/// The underlying NSView for section frame tracking.
final class SectionFrameNSView: NSView {
    var section: SectionFrameType = .sidebar
    weak var registry: Sidebar.FrameRegistry?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerWithRegistry()
    }

    override func removeFromSuperview() {
        unregisterFromRegistry()
        super.removeFromSuperview()
    }

    private func registerWithRegistry() {
        guard window != nil else {
            unregisterFromRegistry()
            return
        }
        switch section {
        case .sidebar:
            registry?.sidebarView = self
        case .favoritesGrid:
            registry?.favoritesGridView = self
        }
    }

    private func unregisterFromRegistry() {
        switch section {
        case .sidebar:
            if registry?.sidebarView === self { registry?.sidebarView = nil }
        case .favoritesGrid:
            if registry?.favoritesGridView === self { registry?.favoritesGridView = nil }
        }
    }

    override var isFlipped: Bool { true }
}
