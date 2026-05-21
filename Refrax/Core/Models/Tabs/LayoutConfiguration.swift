import Foundation

/// Direction of pane expansion
enum ExpansionDirection: String, Codable, Equatable {
    case right
    case left
    case down
    case up
}

/// Layout configuration for multi-page tabs
///
/// Stores complete layout state including:
/// - Which pages are in which positions
/// - Divider positions (as ratios 0.0-1.0)
/// - Which panes are expanded over adjacent slots
/// - Currently focused pane
///
/// All divider positions are stored as ratios (0.0 to 1.0) so they scale with window resizing.
struct LayoutConfiguration: nonisolated Codable, Equatable {
    /// Maps TabPage.id to its position in the layout
    var panePositions: [UUID: PanePosition]
    
    /// Currently focused pane
    var activePaneID: UUID?
    
    /// Divider positions as ratios (0.0 to 1.0)
    /// These correspond to the visual separators between panes:
    /// - horizontalDivider: splits left/right columns (vertical line)
    /// - verticalDivider: splits top/bottom rows (horizontal line)
    var horizontalDivider: Double = 0.5 // Vertical line position (left-right split)
    var verticalDivider: Double = 0.5 // Horizontal line position (top-bottom split)
    
    /// Pane expansions (which panes are expanded over adjacent slots)
    var expansions: [PanePosition: ExpansionDirection] = [:]
    
    /// Layout type (derived from positions)
    var layoutType: LayoutType {
        switch panePositions.count {
        case 1: .single
        case 2: .split
        case 3: .triple
        case 4: .quad
        default: .single
        }
    }
    
    /// Check if a position is covered by an expanded pane
    func isCovered(_ position: PanePosition) -> Bool {
        for (expandedPos, direction) in expansions {
            if covers(position, from: expandedPos, direction: direction) {
                return true
            }
        }
        return false
    }
    
    /// Check if an expansion from origin in given direction covers target position
    private func covers(_ target: PanePosition, from origin: PanePosition, direction: ExpansionDirection) -> Bool {
        switch (origin, direction) {
        case (.topLeft, .right):
            target == .topRight
        case (.topLeft, .down):
            target == .bottomLeft
        case (.topRight, .left):
            target == .topLeft
        case (.topRight, .down):
            target == .bottomRight
        case (.bottomLeft, .right):
            target == .bottomRight
        case (.bottomLeft, .up):
            target == .topLeft
        case (.bottomRight, .left):
            target == .bottomLeft
        case (.bottomRight, .up):
            target == .topRight
        default:
            false
        }
    }
}
