import Foundation

/// Represents a 2D position in the favorites grid using a single integer encoding.
///
/// The position encoding uses the formula: `position = row * 1000 + column`
///
/// This encoding provides:
/// - Stable ordering during drag operations
/// - Easy extraction of row and column coordinates
/// - Natural left-to-right, top-to-bottom reading order
///
/// ## Example
///
/// ```swift
/// let pos = FavoritePosition(row: 0, col: 2) // Position 2
/// print(pos.row) // 0
/// print(pos.column) // 2
/// ```
nonisolated struct FavoritePosition: Equatable, Comparable, Codable {
    /// Encoded position value
    private let value: Int
    
    // MARK: - Constants
    
    /// Multiplier for row encoding (1000 allows up to 1000 columns per row)
    private static let rowMultiplier = 1_000
    
    // MARK: - Initialization
    
    /// Create a position from row and column coordinates.
    ///
    /// - Parameters:
    ///   - row: Zero-based row index
    ///   - col: Zero-based column index
    init(row: Int, col: Int) {
        precondition(row >= 0, "Row must be non-negative")
        precondition(col >= 0, "Column must be non-negative")
        precondition(col < Self.rowMultiplier, "Column must be less than \(Self.rowMultiplier)")
        
        self.value = row * Self.rowMultiplier + col
    }
    
    /// Create a position from encoded integer value.
    ///
    /// - Parameter value: Encoded position (row * 1000 + column)
    init(value: Int) {
        precondition(value >= 0, "Position value must be non-negative")
        self.value = value
    }
    
    // MARK: - Properties
    
    /// Zero-based row index
    var row: Int {
        value / Self.rowMultiplier
    }
    
    /// Zero-based column index
    var column: Int {
        value % Self.rowMultiplier
    }
    
    /// Raw encoded value
    var rawValue: Int {
        value
    }
    
    // MARK: - Comparable
    
    static func < (lhs: FavoritePosition, rhs: FavoritePosition) -> Bool {
        lhs.value < rhs.value
    }
    
    // MARK: - Utility
    
    /// Create position for next column in same row
    func nextColumn() -> FavoritePosition {
        FavoritePosition(row: row, col: column + 1)
    }
    
    /// Create position for next row, first column
    func nextRow() -> FavoritePosition {
        FavoritePosition(row: row + 1, col: 0)
    }
    
    /// Create position offset by given row and column deltas
    func offset(rows: Int, columns: Int) -> FavoritePosition {
        FavoritePosition(row: row + rows, col: column + columns)
    }
}

// MARK: - CustomStringConvertible

extension FavoritePosition: CustomStringConvertible {
    var description: String {
        "(\(row), \(column))"
    }
}

// MARK: - Convenience Extensions

extension Int {
    /// Convert raw position value to FavoritePosition
    nonisolated var asFavoritePosition: FavoritePosition {
        FavoritePosition(value: self)
    }
}
