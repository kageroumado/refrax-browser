import Foundation
import SwiftData

/// Represents a browsing context (e.g., "Personal", "Work") with isolated cookies and cache
@Model
final class BrowsingContext {
    // MARK: - Primary Data

    /// Unique identifier
    @Attribute(.unique, .preserveValueOnDeletion)
    var id: UUID
    
    /// Display name of the context
    var name: String
    
    /// When this context was created
    var createdAt: Date
    
    /// When this context was last used
    var lastUsed: Date
    
    /// Icon name for visual identification
    var iconName: String?
    
    /// Color for visual identification (GroupColor raw value)
    var color: String
    
    /// Whether this is the default context
    var isDefault: Bool
    
    // MARK: - Initialization
    
    init(
        name: String,
        iconName: String? = nil,
        color: String = GroupColor.steel.rawValue,
        isDefault: Bool = false,
    ) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.lastUsed = Date()
        self.iconName = iconName
        self.color = color
        self.isDefault = isDefault
    }
    
    // MARK: - Update Methods
    
    /// Updates the last used timestamp to now.
    func updateLastUsed() {
        lastUsed = Date()
    }
}

// MARK: - Computed Properties

extension BrowsingContext {
    /// String ID for use in other models
    var contextID: String {
        id.uuidString
    }
}

// MARK: - Default Contexts

extension BrowsingContext {
    /// Creates the default personal context.
    static func makeDefault() -> BrowsingContext {
        BrowsingContext(
            name: "Personal",
            iconName: "person.fill",
            color: GroupColor.steel.rawValue,
            isDefault: true,
        )
    }
    
    /// Creates a work context.
    static func makeWork() -> BrowsingContext {
        BrowsingContext(
            name: "Work",
            iconName: "briefcase.fill",
            color: GroupColor.emerald.rawValue,
            isDefault: false,
        )
    }
}
