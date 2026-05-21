import Foundation
import SwiftUI

/// Computes layout for history graph visualization.
///
/// Implements an efficient level allocation algorithm that minimizes vertical
/// space by reusing levels as pages close. Uses actual entry times (not rounded)
/// to prevent visual overlaps.
///
/// ## Algorithm Overview
///
/// The layout engine uses a greedy level allocation strategy with O(n log n) complexity:
///
/// ```
/// Input: Sorted [HistoryEntry]
/// State: [level: freeAfter] dictionary
///
/// For each entry:
///     1. Use actual visitedAt time (not rounded)
///
///     2. If direct navigation from parent:
///        Check if parent's level is free
///        If yes: reuse parent level
///
///     3. Otherwise:
///        level = 0
///        while levelAvailability[level] > entry.start:
///            level++
///
///     4. Allocate:
///        allocations.append((entry, level))
///        levelAvailability[level] = entry.end + buffer
/// ```
///
/// ## Arrow Generation
///
/// Multiple children from the same parent share a vertical trunk:
///
/// ```
/// Parent (level 0)
///    │
///    ├─────→ Child 1 (level 1)
///    │
///    ├─────→ Child 2 (level 2)
///    │
///    └─────→ Child 3 (level 3)
/// ```
///
/// ## Performance
///
/// - **Time**: O(n log n) dominated by initial sort
/// - **Space**: O(n) for nodes and connections
/// - **Target**: Handle 500+ entries at 60fps
///
/// ## Performance Notes
///
/// All computation runs on the MainActor due to project-wide default isolation.
/// For large entry sets, consider throttling or debouncing layout updates.
final class HistoryGraphLayoutEngine {
    // MARK: - Layout Computation

    /// Compute complete layout for history entries asynchronously.
    ///
    /// Provides an async interface for callers. Computation runs on MainActor
    /// due to project-wide default isolation of underlying types.
    ///
    /// - Parameters:
    ///   - entries: History entries to visualize
    ///   - coordinates: Coordinate system for converting time/level to points
    ///   - spaces: Map of space IDs to Space objects for color coding
    /// - Returns: Complete layout with positioned nodes and connection paths
    func computeLayoutAsync(
        entries: [HistoryEntry],
        coordinates: GraphCoordinates,
        spaces: [UUID: Space],
    ) async -> HistoryGraphLayout {
        computeLayout(entries: entries, coordinates: coordinates, spaces: spaces)
    }

    /// Synchronous layout computation.
    ///
    /// - Parameters:
    ///   - entries: History entries to visualize
    ///   - coordinates: Coordinate system for converting time/level to points
    ///   - spaces: Map of space IDs to Space objects for color coding
    /// - Returns: Complete layout with positioned nodes and connection paths
    func computeLayout(
        entries: [HistoryEntry],
        coordinates: GraphCoordinates,
        spaces: [UUID: Space],
    ) -> HistoryGraphLayout {
        let intermediateData = computeIntermediateLayout(
            entries: entries,
            coordinates: coordinates,
            spaces: spaces,
        )
        return buildFinalLayout(from: intermediateData, coordinates: coordinates)
    }

    // MARK: - Intermediate Computation

    /// Computes intermediate layout data without building Paths.
    private func computeIntermediateLayout(
        entries: [HistoryEntry],
        coordinates: GraphCoordinates,
        spaces: [UUID: Space],
    ) -> IntermediateLayoutData {
        // Filter and sort entries
        let sortedEntries = entries
            .sorted { $0.visitedAt < $1.visitedAt }

        // Detect time gaps
        let gaps = GraphCoordinates.detectGaps(in: sortedEntries)

        // Allocate levels for each entry
        let nodeAllocations = allocateLevels(for: sortedEntries, coordinates: coordinates)

        // Create node data
        let nodeData = nodeAllocations.map { allocation in
            IntermediateLayoutData.NodeData(
                entryID: allocation.entry.id,
                entry: allocation.entry,
                level: allocation.level,
                frame: coordinates.rect(for: allocation.entry, at: allocation.level),
                spaceColor: allocation.entry.spaceID.flatMap { spaces[$0]?.color },
            )
        }

        // Create connection data (without Paths)
        let connectionData = computeConnectionData(
            nodeData: nodeData,
            coordinates: coordinates,
        )

        // Calculate total bounds
        let maxLevel = nodeAllocations.map(\.level).max() ?? 0
        let bounds = coordinates.canvasSize(maxLevel: maxLevel, timeRange: coordinates.timeRange)

        return IntermediateLayoutData(
            nodeData: nodeData,
            connectionData: connectionData,
            bounds: bounds,
            timeRange: coordinates.timeRange,
            gaps: gaps,
        )
    }

    /// Computes connection structure data without building Paths.
    private func computeConnectionData(
        nodeData: [IntermediateLayoutData.NodeData],
        coordinates _: GraphCoordinates,
    ) -> [IntermediateLayoutData.ConnectionData] {
        let nodeMap = Dictionary(uniqueKeysWithValues: nodeData.map { ($0.entryID, $0) })

        // Group children by parent
        var childrenByParent: [UUID: [IntermediateLayoutData.NodeData]] = [:]
        for node in nodeData {
            if let parent = node.entry.parent {
                childrenByParent[parent.id, default: []].append(node)
            }
        }

        // Create connection data for each parent-children group
        var connectionData: [IntermediateLayoutData.ConnectionData] = []
        for (parentID, children) in childrenByParent {
            guard let parent = nodeMap[parentID] else { continue }

            // Sort children by level
            let sortedChildren = children.sorted { $0.level < $1.level }

            connectionData.append(IntermediateLayoutData.ConnectionData(
                fromID: parentID,
                toIDs: sortedChildren.map(\.entryID),
                parentFrame: parent.frame,
                childFrames: sortedChildren.map { (level: $0.level, frame: $0.frame) },
            ))
        }

        return connectionData
    }

    /// Allocates discrete levels to minimize vertical space.
    ///
    /// Uses actual entry times (not rounded) to prevent visual overlaps.
    /// Direct navigation attempts to reuse parent's level if available.
    /// Adds small buffer between entries for visual clarity.
    private func allocateLevels(
        for entries: [HistoryEntry],
        coordinates _: GraphCoordinates,
    ) -> [NodeAllocation] {
        var allocations: [NodeAllocation] = []
        allocations.reserveCapacity(entries.count)
        var levelAvailability: [Int: Date] = [:] // level -> time when it becomes free

        // Small buffer to prevent entries from touching at exact boundaries
        let bufferTime: TimeInterval = 1.0 // 1 second

        for entry in entries {
            // Use actual start time for overlap detection
            let startTime = entry.visitedAt

            // Determine end time based on lifecycle
            let endTime: Date = if let closedAt = entry.closedAt {
                closedAt.addingTimeInterval(bufferTime)
            } else {
                // Still open - use current time
                Date().addingTimeInterval(bufferTime)
            }

            // For direct navigation (parent exists and on same level would fit), try same level
            if let parent = entry.parent,
               let parentAllocation = allocations.first(where: { $0.entry.id == parent.id }) {
                // Check if we can place on same level (direct navigation)
                if let freeTime = levelAvailability[parentAllocation.level],
                   startTime >= freeTime {
                    // Same level is available
                    allocations.append(NodeAllocation(entry: entry, level: parentAllocation.level))
                    levelAvailability[parentAllocation.level] = endTime
                    continue
                }
            }

            // Find the lowest available level
            var level = 0
            while true {
                if let freeTime = levelAvailability[level] {
                    if startTime >= freeTime {
                        // This level is free
                        break
                    }
                } else {
                    // Level never used, it's free
                    break
                }
                level += 1
            }

            // Allocate this level
            allocations.append(NodeAllocation(entry: entry, level: level))
            levelAvailability[level] = endTime
        }

        return allocations
    }

    /// Intermediate layout data that can cross thread boundaries.
    private struct IntermediateLayoutData: Sendable {
        let nodeData: [NodeData]
        let connectionData: [ConnectionData]
        let bounds: CGSize
        let timeRange: ClosedRange<Date>
        let gaps: [TimeGap]

        struct NodeData: Sendable {
            let entryID: UUID
            let entry: HistoryEntry
            let level: Int
            let frame: CGRect
            let spaceColor: Color?
        }

        struct ConnectionData: Sendable {
            let fromID: UUID
            let toIDs: [UUID]
            let parentFrame: CGRect
            let childFrames: [(level: Int, frame: CGRect)]
        }
    }

    // MARK: - Final Layout Building (MainActor)

    /// Builds the final layout with Paths from intermediate data.
    @MainActor
    private func buildFinalLayout(
        from data: IntermediateLayoutData,
        coordinates: GraphCoordinates,
    ) -> HistoryGraphLayout {
        // Build nodes
        let nodes = data.nodeData.map { nodeData in
            GraphNode(
                entry: nodeData.entry,
                level: nodeData.level,
                frame: nodeData.frame,
                spaceColor: nodeData.spaceColor,
            )
        }

        // Build connections with Paths
        let connections = data.connectionData.map { connData in
            let path = createMergedPath(
                parentFrame: connData.parentFrame,
                childFrames: connData.childFrames,
                coordinates: coordinates,
            )
            return GraphConnection(
                from: connData.fromID,
                to: connData.toIDs,
                path: path,
            )
        }

        return HistoryGraphLayout(
            nodes: nodes,
            connections: connections,
            bounds: data.bounds,
            timeRange: data.timeRange,
            gaps: data.gaps,
        )
    }

    /// Creates a merged arrow path from parent to multiple children.
    @MainActor
    private func createMergedPath(
        parentFrame: CGRect,
        childFrames: [(level: Int, frame: CGRect)],
        coordinates: GraphCoordinates,
    ) -> Path {
        var path = Path()

        guard !childFrames.isEmpty else { return path }

        // Start from right edge of parent (vertical center)
        let parentEndX = parentFrame.maxX
        let parentCenterY = parentFrame.midY

        path.move(to: CGPoint(x: parentEndX, y: parentCenterY))

        // Drop straight down to the lowest child level
        let maxChildLevel = childFrames.map(\.level).max() ?? 0
        let dropToY = coordinates.y(for: maxChildLevel) + GraphCoordinates.levelHeight / 2

        // Draw vertical line forward then down
        let verticalLineX = parentEndX + 20 // Offset to the right
        path.addLine(to: CGPoint(x: verticalLineX, y: parentCenterY))
        path.addLine(to: CGPoint(x: verticalLineX, y: dropToY))

        // Branch to each child
        for (_, childFrame) in childFrames {
            let childStartX = childFrame.minX
            let childCenterY = childFrame.midY

            // From vertical trunk to child
            path.move(to: CGPoint(x: verticalLineX, y: childCenterY))

            // Add rounded corner
            if abs(childCenterY - dropToY) < 0.1 {
                // Straight horizontal line
                path.addLine(to: CGPoint(x: childStartX, y: childCenterY))
            } else {
                // Curved connection
                let controlPoint = CGPoint(
                    x: verticalLineX + GraphCoordinates.arrowCornerRadius,
                    y: childCenterY,
                )
                path.addQuadCurve(
                    to: CGPoint(x: childStartX, y: childCenterY),
                    control: controlPoint,
                )
            }
        }

        return path
    }
}

// MARK: - Supporting Types

/// Temporary allocation data during layout computation
private struct NodeAllocation {
    let entry: HistoryEntry
    let level: Int
}

// MARK: - Layout Result

/// Complete layout result for the history graph
struct HistoryGraphLayout: Equatable {
    let nodes: [GraphNode]
    let connections: [GraphConnection]
    let bounds: CGSize
    let timeRange: ClosedRange<Date>
    let gaps: [TimeGap]
    
    static func == (lhs: HistoryGraphLayout, rhs: HistoryGraphLayout) -> Bool {
        lhs.nodes.map(\.id) == rhs.nodes.map(\.id) &&
            lhs.connections.map(\.id) == rhs.connections.map(\.id) &&
            lhs.bounds == rhs.bounds &&
            lhs.timeRange == rhs.timeRange &&
            lhs.gaps.map(\.id) == rhs.gaps.map(\.id)
    }
    
    /// Find node by entry ID
    func node(for entryID: UUID) -> GraphNode? {
        nodes.first { $0.entry.id == entryID }
    }
    
    /// Find nodes within a time range
    func nodes(in range: ClosedRange<Date>) -> [GraphNode] {
        nodes.filter { node in
            range.contains(node.entry.visitedAt)
        }
    }
}

/// Represents a positioned node in the graph.
///
/// Node visual representation:
/// ```
/// Normal page (> 5 seconds):
/// ┌─────────────────┐
/// │ Title           │  ← Solid border, space-colored background
/// │ Space name      │
/// └─────────────────┘
///
/// Still open page:
/// ┌──┈┈┈┈┈┈┈┈┈┈┈┈┈┐
/// ┊ Title          ┊  ← Dotted border
/// └──┈┈┈┈┈┈┈┈┈┈┈┈┈┘
///
/// Very short visit (< 5 seconds):
/// ●  ← Simple dot
/// ```
struct GraphNode: Identifiable {
    let id = UUID()
    let entry: HistoryEntry
    let level: Int
    let frame: CGRect
    let spaceColor: Color?
    
    /// Whether this node should be drawn as a dot instead of a rectangle.
    var isDot: Bool {
        let endTime = entry.closedAt ?? Date()
        let duration = endTime.timeIntervalSince(entry.visitedAt)
        return duration < GraphCoordinates.dotThreshold
    }
    
    /// Whether this page is still open (no closedAt timestamp).
    var isOpen: Bool {
        entry.closedAt == nil
    }
}

/// Represents a connection between nodes (arrow path).
///
/// Arrow patterns:
/// ```
/// Single child:
/// Parent ──→ Child
///
/// Multiple children (merged trunk):
/// Parent ──┬──→ Child 1
///          ├──→ Child 2
///          └──→ Child 3
/// ```
struct GraphConnection: Identifiable {
    let id = UUID()
    let from: UUID
    let to: [UUID]
    let path: Path
}
