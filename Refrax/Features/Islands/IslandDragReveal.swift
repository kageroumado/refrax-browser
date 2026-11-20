import AppKit

/// What a press on the page and a drag over the window do to the islands.
///
/// Islands latched open stay through a press on the page: the press gives the keyboard back
/// to the page. Islands up only while the reveal key is held go with the press. A drag
/// carrying links, text, files, or rows that comes over the window brings the islands up as
/// drop targets, and puts them away again when it leaves or ends, unless they were up already.
nonisolated struct IslandDragReveal: Equatable, Sendable {
    /// What a drag over the window carries, as the islands weigh it.
    enum DragKind: Equatable, Sendable {
        /// Links, text, files, or rows: an island can take it.
        case droppable
        /// Anything else, an island cannot.
        case other

        /// Reads a drag's pasteboard types.
        init(types: some Sequence<NSPasteboard.PasteboardType>) {
            let droppable: Set<NSPasteboard.PasteboardType> = [
                IslandPasteboard.tabIDs, .URL, .fileURL, .string, NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            ]
            self = types.contains(where: droppable.contains) ? .droppable : .other
        }
    }

    enum Event: Equatable, Sendable {
        /// The button went down on the page, off every island and control.
        case pressOnPage
        /// A drag came over the window.
        case dragEntered(DragKind)
        /// The drag left the window.
        case dragExited
        /// The drag ended, dropped or not.
        case dragEnded
    }

    enum Action: Equatable, Sendable {
        case none
        /// Let the held islands go.
        case dismiss
        /// The page takes the keyboard back; the latched islands stay.
        case returnKeyboard
        /// Bring the islands up for a drag.
        case reveal
        /// Put away the islands the drag brought up.
        case putAway
    }

    /// The islands are up because a drag brought them.
    private(set) var isRevealedForDrag = false

    /// Answers `event`; `latched` says whether the islands are latched open now.
    mutating func handle(_ event: Event, latched: Bool) -> Action {
        switch event {
        case .pressOnPage:
            return latched ? .returnKeyboard : .dismiss
        case let .dragEntered(kind):
            guard kind == .droppable, !latched, !isRevealedForDrag else { return .none }
            isRevealedForDrag = true
            return .reveal
        case .dragExited:
            return putAway()
        case .dragEnded:
            return putAway()
        }
    }

    private mutating func putAway() -> Action {
        guard isRevealedForDrag else { return .none }
        isRevealedForDrag = false
        return .putAway
    }
}
