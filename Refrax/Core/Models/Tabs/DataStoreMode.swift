import Foundation

/// The data storage mode for a space.
///
/// Determines how browsing data (cookies, cache, localStorage, etc.) is stored
/// and isolated for tabs within a space.
enum DataStoreMode: String, Codable, CaseIterable, Sendable {
    /// Uses the shared default data store.
    ///
    /// All spaces with this mode share cookies, cache, and browsing data.
    /// This is the default mode for normal browsing.
    case global

    /// Uses an isolated persistent data store.
    ///
    /// The space gets its own data store identified by its UUID. Cookies, cache,
    /// and browsing data are isolated from other spaces but persist across sessions.
    case separate

    /// Uses a non-persistent (ephemeral) data store.
    ///
    /// Nothing is written to disk. All browsing data is discarded when the space
    /// is closed or the app quits. History entries are also not recorded.
    case `private`

    /// Whether this mode uses a non-persistent (ephemeral) data store.
    var isPrivate: Bool {
        self == .private
    }

    /// Whether this mode uses an isolated persistent data store.
    var usesSeparateDataStore: Bool {
        self == .separate
    }

    /// Whether this mode uses the global default data store.
    var isGlobal: Bool {
        self == .global
    }

    /// Display name for UI.
    var displayName: String {
        switch self {
        case .global: "Shared"
        case .separate: "Isolated"
        case .private: "Private"
        }
    }

    /// Descriptive text for UI.
    var displayDescription: String {
        switch self {
        case .global:
            "Share cookies and data with other spaces"
        case .separate:
            "Isolated cookies and data, persisted across sessions"
        case .private:
            "No data saved to disk, cleared when closed"
        }
    }

    /// SF Symbol name for the mode.
    var iconName: String {
        switch self {
        case .global: "globe"
        case .separate: "lock.shield"
        case .private: "eye.slash"
        }
    }
}
