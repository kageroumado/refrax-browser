import Foundation
import SwiftData

/// A snapshot of all open tabs at a specific point in time
@Model
final class TabSnapshot {
    // Index for date range queries and latest snapshot lookups
    #Index<TabSnapshot>([\.createdAt])

    // MARK: - Primary Data

    /// Unique identifier
    @Attribute(.unique)
    var id: UUID
    
    /// When this snapshot was created
    var createdAt: Date
    
    /// The browsing context this snapshot belongs to
    var spaceID: UUID?
    
    /// Individual tab items in this snapshot
    @Relationship(deleteRule: .cascade, inverse: \TabSnapshotItem.snapshot)
    var items: [TabSnapshotItem]
    
    /// The ID of the active tab at snapshot time
    var activeTabID: UUID?
    
    /// Hash of the snapshot content for deduplication
    var contentHash: String
    
    // MARK: - Initialization
    
    init(
        spaceID: UUID? = nil,
        items: [TabSnapshotItem] = [],
        activeTabID: UUID? = nil,
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.spaceID = spaceID
        self.items = items
        self.activeTabID = activeTabID
        self.contentHash = Self.calculateHash(items: items, activeTabID: activeTabID)
    }
    
    // MARK: - Hash Calculation
    
    /// Calculate a hash of the snapshot content for comparison
    private static func calculateHash(items: [TabSnapshotItem], activeTabID: UUID?) -> String {
        var hasher = Hasher()
        
        // Hash the tab URLs and positions in order
        for item in items.sorted(by: { $0.position < $1.position }) {
            hasher.combine(item.url.absoluteString)
            hasher.combine(item.position)
            hasher.combine(item.isPinned)
        }
        
        hasher.combine(activeTabID)
        
        return String(hasher.finalize())
    }
    
    /// Recalculate and update the content hash
    func updateHash() {
        contentHash = Self.calculateHash(items: items, activeTabID: activeTabID)
    }
}

// MARK: - Computed Properties

extension TabSnapshot {
    /// Number of tabs in this snapshot
    var tabCount: Int {
        items.count
    }
    
    /// Whether this snapshot has any items
    var isEmpty: Bool {
        items.isEmpty
    }
}

// MARK: - TabSnapshotItem

/// Represents a single tab's state within a snapshot
@Model
final class TabSnapshotItem {
    // MARK: - Primary Data

    /// Unique identifier
    @Attribute(.unique)
    var id: UUID
    
    /// The tab's ID (for correlation with Tab entities)
    var tabID: UUID
    
    /// Current URL of the tab
    var url: URL
    
    /// Page title
    var title: String?
    
    /// Position in the tab bar
    var position: Int
    
    /// Whether the tab is pinned
    var isPinned: Bool
    
    /// Group ID if the tab belongs to a group
    var groupID: UUID?
    
    /// Custom name if user renamed the tab
    var customName: String?
    
    /// The snapshot this item belongs to
    var snapshot: TabSnapshot?

    // MARK: - Visual State

    /// Cached favicon data for display without network fetch.
    ///
    /// Stored as PNG data, max ~10KB. If larger, this is nil and
    /// the UI falls back to a domain-based placeholder.
    var faviconData: Data?

    // MARK: - Navigation State
    
    /// Can go back
    var canGoBack: Bool
    
    /// Can go forward
    var canGoForward: Bool
    
    /// Current history position (for restoration)
    var historyIndex: Int?
    
    // MARK: - Initialization
    
    init(
        tabID: UUID,
        url: URL,
        title: String? = nil,
        position: Int,
        isPinned: Bool = false,
        groupID: UUID? = nil,
        customName: String? = nil,
        faviconData: Data? = nil,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        historyIndex: Int? = nil,
    ) {
        self.id = UUID()
        self.tabID = tabID
        self.url = url
        self.title = title
        self.position = position
        self.isPinned = isPinned
        self.groupID = groupID
        self.customName = customName
        self.faviconData = faviconData
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.historyIndex = historyIndex
    }
}

// MARK: - Identifiable

// extension TabSnapshot: Identifiable {}
// extension TabSnapshotItem: Identifiable {}
