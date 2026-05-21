import Foundation
import SwiftData

/// Persisted app shortcut that appears in the favorites grid.
///
/// App shortcuts provide quick access to app features like the Downloads tray,
/// Bookmarks tray, History tray, and Settings. They appear alongside web-based
/// favorites and can be freely reordered within the grid.
///
/// ## Usage
///
/// ```swift
/// let shortcut = AppShortcut(type: .downloads)
/// context.insert(shortcut)
/// ```
///
/// ## Customization
///
/// Users can customize the display name and color through Settings:
/// - `customName`: Overrides `type.displayName`
/// - `customColor`: Overrides `type.defaultColor`
@Model
final class AppShortcut {
    /// Unique identifier.
    @Attribute(.preserveValueOnDeletion)
    var id: UUID

    /// Raw value for shortcut type.
    ///
    /// Use ``shortcutType`` computed property for type-safe access.
    private var typeRawValue: String

    /// Position in the favorites grid.
    ///
    /// Encoded as `row * 1000 + column` for stable ordering.
    var positionValue: Int

    /// Optional custom color (hex string).
    ///
    /// When set, overrides the default color for this shortcut type.
    var customColor: String?

    /// Optional custom display name.
    ///
    /// When set, overrides the default display name for this shortcut type.
    var customName: String?

    // MARK: - Initialization

    /// Creates a new app shortcut.
    ///
    /// - Parameters:
    ///   - type: The type of app feature this shortcut opens.
    ///   - position: Optional initial position in the grid. Defaults to (0, 0).
    init(type: AppShortcutType, position: FavoritePosition = FavoritePosition(row: 0, col: 0)) {
        self.id = UUID()
        self.typeRawValue = type.rawValue
        self.positionValue = position.rawValue
        self.customColor = nil
        self.customName = nil
    }

    // MARK: - Computed Properties

    /// The type of app feature this shortcut opens.
    var shortcutType: AppShortcutType {
        get {
            AppShortcutType(rawValue: typeRawValue) ?? .settings
        }
        set {
            typeRawValue = newValue.rawValue
        }
    }

    /// Position in the favorites grid.
    var position: FavoritePosition {
        get {
            FavoritePosition(value: positionValue)
        }
        set {
            positionValue = newValue.rawValue
        }
    }

    /// Display name (custom or default).
    var displayName: String {
        let type = AppShortcutType(rawValue: typeRawValue) ?? .settings
        return customName ?? type.displayName
    }

    /// Color hex string (custom or default).
    var color: String {
        let type = AppShortcutType(rawValue: typeRawValue) ?? .settings
        return customColor ?? type.defaultColor
    }

    /// SF Symbol icon name for this shortcut.
    var iconName: String {
        let type = AppShortcutType(rawValue: typeRawValue) ?? .settings
        return type.iconName
    }
}
