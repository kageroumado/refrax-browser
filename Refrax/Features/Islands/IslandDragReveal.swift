import AppKit

/// When the islands come up for a drag and go away after a press on the page.
///
/// A press on the page lets latched islands go only once it proves to be a click: a press
/// that moves is a drag (a link, an image, selected text) that may be on its way to an
/// island. A drag carrying links, text, files, or rows that comes over the window brings the
/// islands up as drop targets, and puts them away again when it leaves or ends, unless they
/// were up already.
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
        /// The pointer moved with the button down.
        case pointerDragged
        /// The button came up.
        case pointerUp
        /// A drag came over the window.
        case dragEntered(DragKind)
        /// The drag left the window.
        case dragExited
        /// The drag ended, dropped or not.
        case dragEnded
    }

    enum Action: Equatable, Sendable {
        case none
        /// Let the revealed islands go.
        case dismiss
        /// Bring the islands up for a drag.
        case reveal
        /// Put away the islands the drag brought up.
        case putAway
    }

    private enum Press: Equatable, Sendable {
        case none
        /// Down on the page with the islands latched; a click if it comes up without moving.
        case pending
        /// It moved: a drag, which keeps the islands.
        case dragged
    }

    private var press = Press.none
    /// The islands are up because a drag brought them.
    private(set) var isRevealedForDrag = false

    /// Answers `event`; `latched` says whether the islands are latched open now.
    mutating func handle(_ event: Event, latched: Bool) -> Action {
        switch event {
        case .pressOnPage:
            guard latched else {
                press = .none
                return .dismiss
            }
            press = .pending
            return .none
        case .pointerDragged:
            if press == .pending {
                press = .dragged
            }
            return .none
        case .pointerUp:
            defer { press = .none }
            return press == .pending ? .dismiss : .none
        case let .dragEntered(kind):
            guard kind == .droppable, !latched, !isRevealedForDrag else { return .none }
            isRevealedForDrag = true
            return .reveal
        case .dragExited:
            return putAway()
        case .dragEnded:
            press = .none
            return putAway()
        }
    }

    private mutating func putAway() -> Action {
        guard isRevealedForDrag else { return .none }
        isRevealedForDrag = false
        return .putAway
    }
}
