import AppKit

/// Borrows a tab's live page and returns it to its previous host when the preview closes.
///
/// A session that `yields` (a table slab beside the current one) holds its page only until
/// another session asks for it, and takes it back when that session lets go, so a docked
/// column or a floating card is always live over a neighboring slab.
final class FloatingPreviewSession {
    private final class Entry {
        weak var session: FloatingPreviewSession?

        init(_ session: FloatingPreviewSession) {
            self.session = session
        }
    }

    /// The yielding sessions, by their ownership ID.
    private static var yieldingSessions: [ObjectIdentifier: Entry] = [:]

    private let yields: Bool
    private weak var page: WebPage?
    private var previousOwner: ObjectIdentifier?
    /// The page was taken from a yielding session, which gets it back if it still wants it.
    private var tookFromYieldingSession = false

    var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    init(yields: Bool = false) {
        self.yields = yields
    }

    @discardableResult
    func acquire(_ page: WebPage, windowID: ObjectIdentifier) -> Bool {
        guard !page.isWebViewInVideoWindow else { return false }
        if self.page === page, page.ownerWindowID == id {
            return true
        }
        let owner = page.ownerWindowID
        let fromYieldingSession = takesOver(page, from: owner)
        guard owner == nil || owner == windowID || owner == id || fromYieldingSession else { return false }
        release()
        previousOwner = owner == id ? nil : owner
        tookFromYieldingSession = fromYieldingSession
        self.page = page
        page.floatingPreviewOwnerID = id
        page.claimOwnership(id: id)
        if yields {
            Self.yieldingSessions[id] = Entry(self)
        }
        return true
    }

    func release() {
        Self.yieldingSessions.removeValue(forKey: id)
        guard let page else { return }
        if page.ownerWindowID == id || page.ownerWindowID == nil {
            if !tookFromYieldingSession {
                page.ownerWindowID = previousOwner
            } else if let previousOwner, Self.yieldingSessions[previousOwner]?.session?.page === page {
                page.ownerWindowID = previousOwner
                page.floatingPreviewOwnerID = previousOwner
            } else {
                page.ownerWindowID = nil
            }
        }
        if page.floatingPreviewOwnerID == id {
            page.floatingPreviewOwnerID = nil
        }
        self.page = nil
        previousOwner = nil
        tookFromYieldingSession = false
    }

    /// Whether this session may take `page` from `owner`: only a yielding session gives its
    /// page up, and only to a session that does not yield.
    private func takesOver(_ page: WebPage, from owner: ObjectIdentifier?) -> Bool {
        guard !yields, let owner, let holder = Self.yieldingSessions[owner]?.session else { return false }
        return holder.page === page
    }

    isolated deinit { release() }
}
