import Foundation
import SwiftData

/// A website's answer to "send you notifications?", keyed by origin.
///
/// One record per origin that asked, shared by every space except private ones: private
/// spaces run in ephemeral data stores, where WebKit denies notifications without asking, so
/// nothing from them is ever stored. Deleting the record returns the site to asking.
///
/// Kept on this Mac: macOS authorizes notifications per Mac, and the delivery statistics
/// change with every notification.
@Model
final class WebNotificationPermission {
    /// The user's decision.
    enum State: String, Codable, CaseIterable, Sendable {
        case granted
        case denied
    }

    @Attribute(.unique)
    var id: UUID = UUID()

    /// The serialized origin (``WebOrigin/string``), e.g. `https://example.com`.
    @Attribute(.unique)
    var origin: String = ""

    var stateRaw: String = State.denied.rawValue

    /// When the site first asked.
    var requestedAt: Date = Date()

    /// When the user last set the state, by answering the prompt or in Settings.
    var decidedAt: Date = Date()

    /// When the site last showed a notification.
    var lastNotificationAt: Date?

    /// How many notifications the site has shown.
    var notificationCount: Int = 0

    init(origin: WebOrigin, state: State, at date: Date = Date()) {
        self.id = UUID()
        self.origin = origin.string
        self.stateRaw = state.rawValue
        self.requestedAt = date
        self.decidedAt = date
    }

    var state: State {
        get { State(rawValue: stateRaw) ?? .denied }
        set { stateRaw = newValue.rawValue }
    }

    /// The parsed origin; nil only for a record written by hand.
    var webOrigin: WebOrigin? {
        WebOrigin(string: origin)
    }
}
