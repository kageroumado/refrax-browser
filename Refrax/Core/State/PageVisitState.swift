import AppKit
import Observation

/// One return destination per window, shared by successive temporary visits.
@Observable
final class PageVisitState {
    struct Destination: Equatable {
        let tabID: Tab.ID
        let spaceID: Space.ID?
        let title: String
        let focusedPageID: TabPage.ID?
    }

    /// The verb for opening a page while keeping the way back, wherever a menu or lens offers it.
    nonisolated static let lookActionTitle = "Look, then Return"

    private(set) var destination: Destination?
    /// When the visit that `destination` belongs to began.
    private(set) var beganAt: Date?
    /// Set while a tab changes what it is (Favorite, Remove from Favorites), so the change
    /// neither ends the visit nor hands the tab to the floating layer.
    var isTransformingIdentity = false
    @ObservationIgnored private var retainedPage: WebPage?
    @ObservationIgnored private weak var responder: NSResponder?
    @ObservationIgnored var authenticationTask: Task<Void, Never>?

    func begin(from tab: Tab, in window: WindowState, page: WebPage?) {
        guard destination == nil else { return }
        destination = Destination(
            tabID: tab.id,
            spaceID: window.activeSpaceID,
            title: tab.displayTitle,
            focusedPageID: window.focusedPageID,
        )
        beganAt = Date()
        retainedPage = page
        page?.temporaryVisitRetentionCount += 1
        responder = window.window?.firstResponder
    }

    func restoreFocus(in window: WindowState) {
        if let pageID = destination?.focusedPageID {
            window.recordInteraction(with: pageID)
        }
        if let view = responder as? NSView, let tabID = destination?.tabID {
            DispatchQueue.main.async { [weak window, weak view] in
                guard let window, let view, window.activeTabID == tabID, view.window === window.window else { return }
                window.window?.makeFirstResponder(view)
            }
        }
    }

    func end() {
        authenticationTask?.cancel()
        authenticationTask = nil
        retainedPage?.temporaryVisitRetentionCount -= 1
        retainedPage = nil
        responder = nil
        destination = nil
        beganAt = nil
    }

    isolated deinit { retainedPage?.temporaryVisitRetentionCount -= 1 }
}
