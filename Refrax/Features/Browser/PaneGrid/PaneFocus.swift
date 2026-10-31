import Foundation

/// Which pane of a split tab holds the window's focus (the page the page card and the address
/// edit act on).
///
/// A click focuses the pane it lands in. A pane appearing, or its window becoming key, keeps
/// the tab's active pane focused: panes appear in no particular order, so letting each one
/// claim focus would leave it on whichever came last.
nonisolated enum PaneFocus {
    nonisolated enum Event: Sendable {
        /// The pane appeared, or its page arrived.
        case appeared
        /// The pane's window became key.
        case windowBecameKey
        /// A click landed in the pane.
        case clicked
    }

    /// Whether `event` on the pane showing `pageID` focuses it, in a tab whose active pane is
    /// `activePageID`.
    static func takesFocus(on event: Event, pageID: UUID, activePageID: UUID?) -> Bool {
        switch event {
        case .clicked: true
        case .appeared, .windowBecameKey: activePageID == nil || pageID == activePageID
        }
    }
}
