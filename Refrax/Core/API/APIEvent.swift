import Foundation

/// Events that occur in the browser and can be subscribed to.
///
/// Events are emitted when browser state changes. Agents can subscribe
/// to specific event types using ``APIEventFilter``.
public enum APIEvent: Sendable {
    // MARK: - Tab Events

    /// A new tab was opened.
    case tabOpened(TabInfo)

    /// A tab was closed.
    case tabClosed(tabID: UUID)

    /// Tab metadata was updated (title, favicon, etc.).
    case tabUpdated(TabInfo)

    /// A tab was activated (focused).
    case tabActivated(TabInfo)

    /// Tab pin state changed.
    case tabPinStateChanged(TabInfo)

    /// Tab was moved (position changed).
    case tabMoved(TabInfo)

    // MARK: - Navigation Events

    /// Navigation started in a tab.
    case navigationStarted(NavigationInfo)

    /// Navigation committed (page is loading).
    case navigationCommitted(NavigationInfo)

    /// Navigation finished (page loaded).
    case navigationFinished(NavigationInfo)

    /// Navigation failed.
    case navigationFailed(tabID: UUID, pageID: UUID, url: String, error: String)

    // MARK: - Space Events

    /// A new space was created.
    case spaceCreated(SpaceInfo)

    /// A space was deleted.
    case spaceDeleted(spaceID: UUID)

    /// Space metadata was updated.
    case spaceUpdated(SpaceInfo)

    /// Active space changed.
    case spaceSwitched(SpaceInfo)

    // MARK: - Group Events

    /// A new group was created.
    case groupCreated(TabGroupInfo)

    /// A group was deleted.
    case groupDeleted(groupID: UUID)

    /// Group metadata was updated.
    case groupUpdated(TabGroupInfo)

    // MARK: - Browser State Events

    /// Tab list structure changed (add/remove/reorder).
    case tabListChanged(version: UInt64)

    /// Tab content changed (titles, favicons, etc.).
    case tabContentChanged(version: UInt64)
}

// MARK: - Event Filter

/// Filter for subscribing to specific event types.
public struct APIEventFilter: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    // MARK: - Tab Filters

    /// Tab opened events.
    public static let tabOpened = APIEventFilter(rawValue: 1 << 0)

    /// Tab closed events.
    public static let tabClosed = APIEventFilter(rawValue: 1 << 1)

    /// Tab updated events.
    public static let tabUpdated = APIEventFilter(rawValue: 1 << 2)

    /// Tab activated events.
    public static let tabActivated = APIEventFilter(rawValue: 1 << 3)

    /// Tab pin state changed events.
    public static let tabPinStateChanged = APIEventFilter(rawValue: 1 << 4)

    /// Tab moved events.
    public static let tabMoved = APIEventFilter(rawValue: 1 << 5)

    /// All tab events.
    public static let allTabEvents: APIEventFilter = [
        .tabOpened, .tabClosed, .tabUpdated, .tabActivated, .tabPinStateChanged, .tabMoved,
    ]

    // MARK: - Navigation Filters

    /// Navigation started events.
    public static let navigationStarted = APIEventFilter(rawValue: 1 << 6)

    /// Navigation committed events.
    public static let navigationCommitted = APIEventFilter(rawValue: 1 << 7)

    /// Navigation finished events.
    public static let navigationFinished = APIEventFilter(rawValue: 1 << 8)

    /// Navigation failed events.
    public static let navigationFailed = APIEventFilter(rawValue: 1 << 9)

    /// All navigation events.
    public static let allNavigationEvents: APIEventFilter = [
        .navigationStarted, .navigationCommitted, .navigationFinished, .navigationFailed,
    ]

    // MARK: - Space Filters

    /// Space created events.
    public static let spaceCreated = APIEventFilter(rawValue: 1 << 10)

    /// Space deleted events.
    public static let spaceDeleted = APIEventFilter(rawValue: 1 << 11)

    /// Space updated events.
    public static let spaceUpdated = APIEventFilter(rawValue: 1 << 12)

    /// Space switched events.
    public static let spaceSwitched = APIEventFilter(rawValue: 1 << 13)

    /// All space events.
    public static let allSpaceEvents: APIEventFilter = [
        .spaceCreated, .spaceDeleted, .spaceUpdated, .spaceSwitched,
    ]

    // MARK: - Group Filters

    /// Group created events.
    public static let groupCreated = APIEventFilter(rawValue: 1 << 14)

    /// Group deleted events.
    public static let groupDeleted = APIEventFilter(rawValue: 1 << 15)

    /// Group updated events.
    public static let groupUpdated = APIEventFilter(rawValue: 1 << 16)

    /// All group events.
    public static let allGroupEvents: APIEventFilter = [
        .groupCreated, .groupDeleted, .groupUpdated,
    ]

    // MARK: - State Filters

    /// Tab list structure changed.
    public static let tabListChanged = APIEventFilter(rawValue: 1 << 17)

    /// Tab content changed.
    public static let tabContentChanged = APIEventFilter(rawValue: 1 << 18)

    /// All state change events.
    public static let allStateEvents: APIEventFilter = [
        .tabListChanged, .tabContentChanged,
    ]

    // MARK: - Convenience

    /// All events.
    public static let all: APIEventFilter = [
        .allTabEvents, .allNavigationEvents, .allSpaceEvents, .allGroupEvents, .allStateEvents,
    ]
}

// MARK: - Event Filter Matching

public extension APIEvent {
    /// Returns the filter flag that matches this event type.
    var filterFlag: APIEventFilter {
        switch self {
        case .tabOpened: .tabOpened
        case .tabClosed: .tabClosed
        case .tabUpdated: .tabUpdated
        case .tabActivated: .tabActivated
        case .tabPinStateChanged: .tabPinStateChanged
        case .tabMoved: .tabMoved
        case .navigationStarted: .navigationStarted
        case .navigationCommitted: .navigationCommitted
        case .navigationFinished: .navigationFinished
        case .navigationFailed: .navigationFailed
        case .spaceCreated: .spaceCreated
        case .spaceDeleted: .spaceDeleted
        case .spaceUpdated: .spaceUpdated
        case .spaceSwitched: .spaceSwitched
        case .groupCreated: .groupCreated
        case .groupDeleted: .groupDeleted
        case .groupUpdated: .groupUpdated
        case .tabListChanged: .tabListChanged
        case .tabContentChanged: .tabContentChanged
        }
    }

    /// Checks if this event matches a filter.
    func matches(_ filter: APIEventFilter) -> Bool {
        filter.contains(filterFlag)
    }
}
