import AppKit

/// Geometry of a browser window: frame plus the chrome dimensions the user
/// controls by dragging (sidebar width, inspector width).
///
/// Captured when a window closes and reapplied to newly created windows, so
/// window size survives the gap AppKit state restoration doesn't cover:
/// restoration only encodes windows still open at quit, while a window
/// created after the last one was closed (Dock click, Cmd+N) starts from
/// scratch.
struct SavedWindowGeometry: Codable {
    var frameX: Double
    var frameY: Double
    var frameWidth: Double
    var frameHeight: Double
    var sidebarWidth: Double
    var isSidebarCollapsed: Bool
    var inspectorWidth: Double

    var frame: NSRect {
        NSRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
    }

    init(
        frame: NSRect,
        sidebarWidth: CGFloat,
        isSidebarCollapsed: Bool,
        inspectorWidth: CGFloat,
    ) {
        frameX = frame.origin.x
        frameY = frame.origin.y
        frameWidth = frame.size.width
        frameHeight = frame.size.height
        self.sidebarWidth = sidebarWidth
        self.isSidebarCollapsed = isSidebarCollapsed
        self.inspectorWidth = inspectorWidth
    }
}

/// Persists the geometry of the most recently closed browser window.
///
/// Stores one record per screen (keyed by screen name and resolution) plus a
/// most-recent fallback, so a window reopened on the same display reuses the
/// size and position it last had there, while a new display still gets a
/// sensible starting point.
@MainActor
enum WindowGeometryStore {
    private static let defaultsKey = "WindowGeometryStore.geometryByScreen"
    private static let fallbackKey = "last"

    /// Saves the geometry of a closing window under its screen's key and as
    /// the most-recent fallback.
    ///
    /// Callers should skip fullscreen windows — a fullscreen frame is not a
    /// useful size for a regular window.
    static func save(_ geometry: SavedWindowGeometry, screen: NSScreen?) {
        var entries = load()
        entries[key(for: screen)] = geometry
        entries[fallbackKey] = geometry
        store(entries)
    }

    /// Returns the geometry to apply to a new window: the record for the
    /// given screen if one exists, otherwise the most recently saved one.
    static func restore(for screen: NSScreen?) -> SavedWindowGeometry? {
        let entries = load()
        return entries[key(for: screen)] ?? entries[fallbackKey]
    }

    private static func key(for screen: NSScreen?) -> String {
        guard let screen else { return fallbackKey }
        return "\(screen.localizedName) \(Int(screen.frame.width))x\(Int(screen.frame.height))"
    }

    private static func load() -> [String: SavedWindowGeometry] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let entries = try? JSONDecoder().decode([String: SavedWindowGeometry].self, from: data)
        else { return [:] }
        return entries
    }

    private static func store(_ entries: [String: SavedWindowGeometry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
