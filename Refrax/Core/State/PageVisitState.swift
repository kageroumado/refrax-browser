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

    private(set) var destination: Destination?
    var isTransformingIdentity = false

    func replaceIdentity(of original: Tab.ID, with tab: Tab) {
        guard let prior = destination, prior.tabID == original else { return }
        destination = Destination(tabID: tab.id, spaceID: prior.spaceID, title: tab.displayTitle, focusedPageID: tab.activePage.id)
    }
    @ObservationIgnored private var retainedPage: WebPage?
    @ObservationIgnored private weak var responder: NSResponder?
    @ObservationIgnored var authenticationTask: Task<Void, Never>?

    func begin(from tab: Tab, in window: WindowState, page: WebPage?) {
        guard destination == nil else { return }
        destination = Destination(tabID: tab.id, spaceID: window.activeSpaceID,
                                  title: tab.displayTitle, focusedPageID: window.focusedPageID)
        retainedPage = page
        page?.temporaryVisitRetentionCount += 1
        responder = window.window?.firstResponder
    }

    func restoreFocus(in window: WindowState) {
        if let pageID = destination?.focusedPageID { window.recordInteraction(with: pageID) }
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
    }

    isolated deinit { retainedPage?.temporaryVisitRetentionCount -= 1 }
}
