import AppKit

/// Borrows a tab's live page and returns it to its previous host when the preview closes.
final class FloatingPreviewSession {
    private weak var page: WebPage?
    private var previousOwner: ObjectIdentifier?

    var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    @discardableResult
    func acquire(_ page: WebPage, windowID: ObjectIdentifier) -> Bool {
        guard !page.isWebViewInVideoWindow,
              page.ownerWindowID == nil || page.ownerWindowID == windowID || page.ownerWindowID == id else { return false }
        if self.page === page {
            return true
        }
        release()
        previousOwner = page.ownerWindowID
        self.page = page
        page.floatingPreviewOwnerID = id
        page.claimOwnership(id: id)
        return true
    }

    func release() {
        guard let page else { return }
        if page.ownerWindowID == id || page.ownerWindowID == nil {
            page.ownerWindowID = previousOwner
        }
        if page.floatingPreviewOwnerID == id {
            page.floatingPreviewOwnerID = nil
        }
        self.page = nil
        previousOwner = nil
    }

    isolated deinit { release() }
}
