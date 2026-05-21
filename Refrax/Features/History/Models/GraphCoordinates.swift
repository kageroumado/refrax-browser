import Foundation
import SwiftUI

/// Coordinate system for converting between time/level space and screen points.
///
/// Manages the mapping between logical history data (time + discrete levels) and
/// Canvas drawing coordinates. Provides zoom level control and layout constants.
///
/// ## Coordinate System
///
/// ```
/// Time Axis (X):
/// ├─ 21:00 prev day ────────────────── 03:00 next day
/// │   0 points                          ~7200 points (at standard zoom)
/// │
/// │  Zoom levels adjust points-per-minute:
/// │  • Extreme: 20 pt/min (highly zoomed)
/// │  • Detailed: 6.67 pt/min
/// │  • Standard: 3.33 pt/min (default)
/// │  • Overview: 1.67 pt/min
/// │  • Compressed: 0.83 pt/min (wide view)
///
/// Level Axis (Y):
/// ├─ Level 0 (y = 0)
/// ├─ Level 1 (y = 40)  [32pt height + 8pt spacing]
/// ├─ Level 2 (y = 80)
/// └─ Level N (y = N * 40)
/// ```
///
/// ## Usage
///
/// ```swift
/// let coords = GraphCoordinates(zoomLevel: .standard, date: Date())
///
/// // Convert time to x coordinate
/// let x = coords.x(for: entry.visitedAt)
///
/// // Convert level to y coordinate
/// let y = coords.y(for: level)
///
/// // Calculate node frame
/// let rect = coords.rect(for: entry, at: level)
/// ```
struct GraphCoordinates: Equatable {
    // MARK: - Scale Constants
    
    /// Discrete zoom levels for the timeline.
    ///
    /// Each level provides a different points-per-minute scale, optimized for
    /// different viewing scenarios from detailed inspection to day overview.
    enum ZoomLevel: CaseIterable, Equatable {
        /// 5 minutes per 100pt (20pt/min) - Maximum detail
        case extremeZoom
        /// 15 minutes per 100pt (≈6.67pt/min) - Detailed view
        case detailed
        /// 30 minutes per 100pt (≈3.33pt/min) - Standard view (default)
        case standard
        /// 1 hour per 100pt (≈1.67pt/min) - Overview
        case overview
        /// 2 hours per 100pt (≈0.83pt/min) - Compressed day view
        case compressed
        
        var pointsPerMinute: CGFloat {
            switch self {
            case .extremeZoom: 20.0
            case .detailed: 100.0 / 15.0 // ≈6.67
            case .standard: 100.0 / 30.0 // ≈3.33
            case .overview: 100.0 / 60.0 // ≈1.67
            case .compressed: 100.0 / 120.0 // ≈0.83
            }
        }
        
        var description: String {
            switch self {
            case .extremeZoom: "5 min"
            case .detailed: "15 min"
            case .standard: "30 min"
            case .overview: "1 hour"
            case .compressed: "2 hours"
            }
        }
    }
    
    // MARK: - Layout Constants
    
    /// Height of each discrete level in points
    static let levelHeight: CGFloat = 32.0
    
    /// Vertical spacing between levels in points
    static let levelSpacing: CGFloat = 8.0
    
    /// Minimum width for page rectangles (15 minutes worth of pixels)
    static let minPageWidth: CGFloat = 100.0
    
    /// Minimum width for "dot" interactions (very short visits)
    static let dotWidth: CGFloat = 8.0
    
    /// Threshold for showing dot vs rectangle (in seconds)
    static let dotThreshold: TimeInterval = 5.0
    
    /// Padding around page rectangles
    static let pageRectPadding: CGFloat = 4.0
    
    /// Arrow line width
    static let arrowLineWidth: CGFloat = 1.5
    
    /// Arrow corner radius for rounded bends
    static let arrowCornerRadius: CGFloat = 8.0
    
    /// Time gap compression threshold (in minutes)
    static let gapCompressionThreshold: TimeInterval = 30 * 60 // 30 minutes
    
    /// Compressed gap width in points
    static let compressedGapWidth: CGFloat = 60.0
    
    // MARK: - Properties
    
    /// Current zoom level
    let zoomLevel: ZoomLevel
    
    /// Reference date (start of the day being displayed)
    let referenceDate: Date
    
    /// Time range being displayed (21:00 prev day to 03:00 next day)
    let timeRange: ClosedRange<Date>
    
    // MARK: - Initialization
    
    init(zoomLevel: ZoomLevel = .standard, date: Date) {
        self.zoomLevel = zoomLevel
        
        // Calculate reference date (start of selected day)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        self.referenceDate = startOfDay
        
        // Calculate time range: 21:00 prev day to 03:00 next day
        let startTime = calendar.date(byAdding: .hour, value: -3, to: startOfDay)!
        let endTime = calendar.date(byAdding: .hour, value: 27, to: startOfDay)!
        self.timeRange = startTime ... endTime
    }
    
    // MARK: - Coordinate Conversion
    
    /// Convert a date to x-coordinate
    func x(for date: Date) -> CGFloat {
        let timeInterval = date.timeIntervalSince(timeRange.lowerBound)
        let minutes = timeInterval / 60.0
        return CGFloat(minutes) * zoomLevel.pointsPerMinute
    }
    
    /// Convert an x-coordinate to date
    func date(for x: CGFloat) -> Date {
        let minutes = Double(x / zoomLevel.pointsPerMinute)
        return timeRange.lowerBound.addingTimeInterval(minutes * 60.0)
    }
    
    /// Convert a level to y-coordinate (top edge)
    func y(for level: Int) -> CGFloat {
        CGFloat(level) * (Self.levelHeight + Self.levelSpacing)
    }
    
    /// Calculate rect for a history entry at a specific level.
    ///
    /// Handles both normal pages (rectangles) and very short visits (dots).
    /// Open tabs extend to current time instead of +15 minutes.
    func rect(for entry: HistoryEntry, at level: Int) -> CGRect {
        let startX = x(for: entry.visitedAt)
        
        // Determine end time based on lifecycle
        let endTime: Date = if let closedAt = entry.closedAt {
            closedAt
        } else {
            // Still open - extend to current time
            Date()
        }
        
        let endX = x(for: endTime)
        let duration = endTime.timeIntervalSince(entry.visitedAt)
        
        // Calculate width based on lifecycle duration
        let calculatedWidth = max(endX - startX, 0)
        
        // Scale dot size with zoom level for very short visits
        let scaledDotWidth = Self.dotWidth * (zoomLevel.pointsPerMinute / 3.33) // Scale relative to standard zoom
        
        let width: CGFloat = if duration < Self.dotThreshold {
            scaledDotWidth
        } else if calculatedWidth < Self.minPageWidth {
            Self.minPageWidth
        } else {
            calculatedWidth
        }
        
        let yPos = y(for: level)
        
        return CGRect(
            x: startX,
            y: yPos,
            width: width,
            height: Self.levelHeight,
        )
    }
    
    /// Calculate total canvas size for given entries and max level
    func canvasSize(maxLevel: Int, timeRange: ClosedRange<Date>) -> CGSize {
        let width = x(for: timeRange.upperBound)
        let height = y(for: maxLevel + 1) // +1 for padding at bottom
        return CGSize(width: width, height: height)
    }
}

// MARK: - Time Gap Detection

extension GraphCoordinates {
    /// Detect significant time gaps in browsing history.
    ///
    /// Gaps longer than 30 minutes are compressed in the visualization to
    /// save horizontal space while maintaining temporal accuracy.
    static func detectGaps(in entries: [HistoryEntry]) -> [TimeGap] {
        guard entries.count > 1 else { return [] }
        
        let sorted = entries.sorted { $0.visitedAt < $1.visitedAt }
        var gaps: [TimeGap] = []
        
        for i in 0 ..< (sorted.count - 1) {
            let current = sorted[i]
            let next = sorted[i + 1]
            
            let currentEnd = current.closedAt ?? current.visitedAt
            let gapDuration = next.visitedAt.timeIntervalSince(currentEnd)
            
            if gapDuration >= gapCompressionThreshold {
                gaps.append(TimeGap(
                    startDate: currentEnd,
                    endDate: next.visitedAt,
                    duration: gapDuration,
                ))
            }
        }
        
        return gaps
    }
}

/// Represents a time gap in browsing history.
///
/// Gaps are displayed as compressed regions with duration labels:
/// ```
/// ├─── content ───┤  ⚡ 2h 15m ⚡  ├─── content ───┤
///                  ↑ Compressed gap indicator
/// ```
struct TimeGap: Identifiable, Equatable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval

    static func == (lhs: TimeGap, rhs: TimeGap) -> Bool {
        lhs.startDate == rhs.startDate && lhs.endDate == rhs.endDate && lhs.duration == rhs.duration
    }

    var durationDescription: String {
        let hours = Int(duration / 3_600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3_600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
