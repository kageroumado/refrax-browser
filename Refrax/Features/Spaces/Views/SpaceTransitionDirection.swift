import Foundation

/// Direction of space transition for animated tab list changes.
///
/// Determines which way content slides when switching between spaces:
/// - `.left`: Selection moved left (previous space) → old content slides right, new slides in from left
/// - `.right`: Selection moved right (next space) → old content slides left, new slides in from right
enum SpaceTransitionDirection {
    case left
    case right
    
    /// Calculate transition direction based on index change.
    ///
    /// - Parameters:
    ///   - oldIndex: Index of the previous space
    ///   - newIndex: Index of the newly selected space
    /// - Returns: Direction for the transition animation
    static func direction(from oldIndex: Int, to newIndex: Int) -> SpaceTransitionDirection {
        newIndex > oldIndex ? .right : .left
    }
}
