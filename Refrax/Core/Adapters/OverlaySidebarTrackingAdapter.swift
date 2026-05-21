import AppKit

/// Custom sidebar tracking adapter for overlay sidebars.
///
/// This class wraps a `_NSSplitViewPartitionAdapter` to provide custom
/// `sidebarDividerPosition` while delegating all other protocol methods
/// (including `isCollapsed`) to the wrapped adapter.
///
/// ## Why Wrapping?
///
/// AppKit provides two sidebar tracking adapters:
///
/// - **`_NSSplitViewPartitionAdapter`**: Full implementation that queries a real split view
/// - **`_NSOSPSidebarTrackingAdapter`**: Minimal implementation that crashes on `isCollapsed`
///
/// For overlay sidebars where toolbar items need to track a virtual position,
/// we need an adapter that:
/// 1. Returns our custom overlay position (not the real split view position)
/// 2. Still implements `isCollapsed` properly (required by toolbar validation)
///
/// Since `_NSSplitViewPartitionAdapter` is a private class that can't be subclassed
/// (linker won't find the symbol), we wrap it instead and forward all protocol methods.
///
/// ## Usage
///
/// ```swift
/// let adapter = OverlaySidebarTrackingAdapter(splitView: splitViewController.splitView)
/// adapter.overrideDividerPosition = 280.0  // Custom overlay position
///
/// themeFrame.sidebarTrackingAdapter = adapter
/// trackingSeparatorItem._setPartitionAdapter(adapter)
/// ```
///
/// ## Thread Safety
///
/// This class should only be accessed from the main thread.
final nonisolated class OverlaySidebarTrackingAdapter: NSObject, NSSidebarTrackingAdapter {
    /// The wrapped split view adapter that handles isCollapsed and other queries.
    /// Accessed via KVC since the class symbol isn't exported.
    private let wrappedAdapter: NSObject

    /// When set, this value is returned for sidebarDividerPosition.
    /// Set to nil to use the real split view position from the wrapped adapter.
    /// Setting this property triggers KVO notifications for `sidebarDividerPosition`
    /// and `logicalDividerPosition` so observers (like NSToolbar) update.
    ///
    /// KVO notifications are only fired when the value actually changes to prevent
    /// unnecessary toolbar relayouts.
    var overrideDividerPosition: CGFloat? {
        get { _overrideDividerPosition }
        set {
            let valueChanged: Bool = switch (newValue, _overrideDividerPosition) {
            case (.none, .none):
                false
            case (.some, .none), (.none, .some):
                true
            case let (.some(new), .some(old)):
                abs(new - old) > 0.1
            }

            guard valueChanged else { return }

            willChangeValue(forKey: "sidebarDividerPosition")
            willChangeValue(forKey: "logicalDividerPosition")
            _overrideDividerPosition = newValue
            didChangeValue(forKey: "logicalDividerPosition")
            didChangeValue(forKey: "sidebarDividerPosition")
        }
    }

    private var _overrideDividerPosition: CGFloat?

    /// Creates an adapter wrapping a split view.
    ///
    /// - Parameters:
    ///   - splitView: The split view to track
    ///   - dividerIndex: Which divider to track (0 = first divider)
    ///   - isTrailingDivider: Whether the sidebar is on the trailing side
    init(splitView: NSSplitView, dividerIndex: Int = 0, isTrailingDivider: Bool = false) {
        guard let adapterClass = NSClassFromString("_NSSplitViewPartitionAdapter") as? NSObject.Type else {
            fatalError("_NSSplitViewPartitionAdapter not found")
        }
        self.wrappedAdapter = adapterClass.init()
        super.init()

        wrappedAdapter.setValue(splitView, forKey: "splitView")
        wrappedAdapter.setValue(dividerIndex, forKey: "splitViewDividerIndex")
        wrappedAdapter.setValue(isTrailingDivider, forKey: "sidebarIsTrailingDivider")
    }

    // MARK: - NSSidebarTrackingAdapter (Required)

    var sidebarDividerPosition: Double {
        if let override = overrideDividerPosition {
            return Double(override)
        }
        return wrappedAdapter.value(forKey: "sidebarDividerPosition") as? Double ?? 0
    }

    var depthOfView: Int64 {
        wrappedAdapter.value(forKey: "depthOfView") as? Int64 ?? 0
    }

    var representedView: NSObject {
        wrappedAdapter.value(forKey: "representedView") as? NSObject ?? wrappedAdapter
    }

    // MARK: - NSSidebarTrackingAdapter (Optional - Critical)

    /// Always returns false so toolbar items use sidebar styling (44px height).
    ///
    /// When `isCollapsed` is true, AppKit sets `inGlassSidebar = false` on toolbar
    /// item viewers, which changes their sizing from 44px to 48px. By always
    /// reporting false, we ensure consistent 44px sizing for both the real sidebar
    /// and the overlay sidebar.
    var isCollapsed: Bool {
        false
    }

    var overlaidAsSidebar: Bool {
        wrappedAdapter.value(forKey: "overlaidAsSidebar") as? Bool ?? false
    }

    func isOverlaidAsSidebar() -> Bool {
        overlaidAsSidebar
    }

    // MARK: - NSSidebarTrackingAdapter (Optional - Other)

    var logicalDividerPosition: Double {
        if let override = overrideDividerPosition {
            return Double(override)
        }
        return wrappedAdapter.value(forKey: "logicalDividerPosition") as? Double ?? 0
    }

    var isValidConfiguration: Bool {
        wrappedAdapter.value(forKey: "isValidConfiguration") as? Bool ?? false
    }

    var minimumDividerPosition: Double {
        wrappedAdapter.value(forKey: "minimumDividerPosition") as? Double ?? 0
    }

    var maximumDividerPosition: Double {
        wrappedAdapter.value(forKey: "maximumDividerPosition") as? Double ?? 0
    }

    var dividerWidth: Double {
        wrappedAdapter.value(forKey: "dividerWidth") as? Double ?? 1
    }

    var dividerCursorRect: CGRect {
        wrappedAdapter.value(forKey: "dividerCursorRect") as? CGRect ?? .zero
    }

    private var _sidebarAdditionalSafeAreaInsets: NSEdgeInsets = .init()

    var sidebarAdditionalSafeAreaInsets: NSEdgeInsets {
        get { _sidebarAdditionalSafeAreaInsets }
        set { _sidebarAdditionalSafeAreaInsets = newValue }
    }

    func setDividerPosition(_ position: Double) {
        _ = wrappedAdapter.perform(NSSelectorFromString("setDividerPosition:"), with: position)
    }

    func toggleSidebar(_ sender: Any?) {
        _ = wrappedAdapter.perform(NSSelectorFromString("toggleSidebar:"), with: sender)
    }
}
