import Foundation
import Observation

/// A question a page is waiting on the user to answer.
///
/// `origin` is the host of the frame that asked, as the engine reports it; the UI shows it
/// so a page can't pass its question off as another site's.
enum PageQuestion: Hashable {
    case alert(message: String, origin: String)
    case confirm(message: String, origin: String)
    case prompt(message: String, defaultText: String?, origin: String)
    /// `beforeunload`: the page asks to keep the user from leaving.
    case leavePage(origin: String)
    case permission(kind: PermissionKind, origin: String)
    /// A store page's "Add to Refrax" button, before anything is downloaded.
    case installExtension(name: String, store: String, origin: String)

    var origin: String {
        switch self {
        case let .alert(_, origin), let .confirm(_, origin), let .prompt(_, _, origin),
             let .leavePage(origin), let .permission(_, origin), let .installExtension(_, _, origin):
            origin
        }
    }
}

/// The user's answer to a ``PageQuestion``.
enum PageAnswer: Hashable {
    /// OK, Leave, Install, or Allow Once.
    case accept
    /// OK on a text prompt.
    case text(String)
    /// Always Allow: grant and remember for the site.
    case acceptAndRemember
    /// Cancel, Stay, or Don't Allow. Also the answer to a question nobody got to see.
    case decline
}

/// The questions one page is waiting on, answered one at a time in the page's own pane.
///
/// Questions belong to their page: a background tab's question waits until the tab is shown,
/// and never appears over another site. A navigation or the page's teardown declines
/// everything still pending, so a page never waits on a question that can no longer be seen.
@Observable
final class PagePrompts {
    /// The most questions a page may have waiting; later ones are declined unseen.
    private static let queueLimit = 3

    struct Pending: Identifiable {
        let id = UUID()
        let question: PageQuestion
        fileprivate let continuation: CheckedContinuation<PageAnswer, Never>
    }

    /// The question on screen for this page.
    private(set) var current: Pending?
    @ObservationIgnored private var waiting: [Pending] = []

    /// Queues `question` and suspends until the user answers it or it's dismissed.
    func ask(_ question: PageQuestion) async -> PageAnswer {
        guard waiting.count + (current == nil ? 0 : 1) < Self.queueLimit else { return .decline }
        return await withCheckedContinuation { continuation in
            let pending = Pending(question: question, continuation: continuation)
            if current == nil {
                current = pending
            } else {
                waiting.append(pending)
            }
        }
    }

    /// Answers the question on screen and shows the next one.
    func answer(_ answer: PageAnswer) {
        guard let current else { return }
        self.current = waiting.isEmpty ? nil : waiting.removeFirst()
        current.continuation.resume(returning: answer)
    }

    /// Declines every pending question.
    func dismissAll() {
        let pending = [current].compactMap(\.self) + waiting
        current = nil
        waiting.removeAll()
        for item in pending {
            item.continuation.resume(returning: .decline)
        }
    }
}
