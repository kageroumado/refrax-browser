import CoreGraphics
import Foundation

/// A stationary pause over a row expresses the intent to combine two tabs.
nonisolated struct IslandJoinDwell {
    static let delay: TimeInterval = 0.6
    private static let tolerance: CGFloat = 6
    private(set) var candidateID: UUID?
    private(set) var beganAt: Date?
    private var anchor: CGPoint = .zero

    mutating func update(candidate: UUID?, at point: CGPoint, now: Date = .now) -> Bool {
        guard candidate != candidateID || hypot(point.x - anchor.x, point.y - anchor.y) > Self.tolerance else { return false }
        candidateID = candidate
        anchor = point
        beganAt = candidate == nil ? nil : now
        return true
    }

    func ready(at now: Date = .now) -> UUID? {
        guard let beganAt, now.timeIntervalSince(beganAt) >= Self.delay else { return nil }
        return candidateID
    }
}
