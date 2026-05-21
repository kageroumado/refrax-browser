import AppKit
import SwiftUI

/// NSHostingView subclass used directly as NSTableView cell views.
///
/// By subclassing NSHostingView directly instead of wrapping it in a container
/// NSView, we eliminate one view layer, four Auto Layout constraints, and the
/// recursive `_layoutSubtreeWithOldSize:` calls the extra nesting caused.
///
/// ## Sizing
///
/// `sizingOptions` is set to empty (`[]`) because the table view controls
/// row height via `tableView(_:heightOfRow:)`. This eliminates Auto Layout
/// constraint creation/updates inside the hosting view, significantly
/// reducing layout cost per cell.
final class CellHostingView: NSHostingView<SidebarCellContent> {
    init(
        identifier: NSUserInterfaceItemIdentifier,
        initialContent: SidebarCellContent,
    ) {
        super.init(rootView: initialContent)
        self.identifier = identifier
        self.sizingOptions = []
    }

    @available(*, unavailable)
    @MainActor @preconcurrency required init?(coder: NSCoder) { fatalError() }
    
    @available(*, unavailable)
    @MainActor @preconcurrency required init(rootView: SidebarCellContent) {
        fatalError("init(rootView:) has not been implemented")
    }
    
    /// Prepare for cell reuse. Matches Apple's internal `ListTableCellView`
    /// pattern — signals to SwiftUI that the view is being recycled, allowing
    /// it to optimize internal state transitions.
    override func prepareForReuse() {
        super.prepareForReuse()
    }

    /// Update the hosted SwiftUI content. SwiftUI diffs the concrete
    /// `SidebarCellContent` struct field-by-field — much faster than
    /// AnyView's type-erased comparison.
    func updateContent(_ content: SidebarCellContent) {
        rootView = content
    }

    // MARK: - First Mouse Support

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// When the window isn't key, return self so our `acceptsFirstMouse` is
    /// respected. Without this, AppKit's hit test reaches internal NSHostingView
    /// subviews that don't accept first mouse, consuming the click for window
    /// activation instead of forwarding it to the cell content.
    ///
    /// No mouse event forwarding is needed — NSHostingView's `mouseDown`
    /// dispatches to SwiftUI's internal hit testing, which finds the correct
    /// gesture handler regardless of which AppKit view received the event.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if window?.isKeyWindow == false {
            return self
        }
        return super.hitTest(point)
    }
}
