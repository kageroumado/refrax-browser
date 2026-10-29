import Foundation

/// A viewport region in desktop points. Its scale is independent of the preview's frame.
nonisolated struct FloatingPageRegion: Codable, Equatable, Sendable {
    let sourceURL: URL
    let viewportSize: CGSize
    var rect: CGRect
    var scale: Double = 1

    var isValid: Bool {
        viewportSize.width.isFinite && viewportSize.height.isFinite
            && viewportSize.width > 0 && viewportSize.height > 0
            && rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite
            && rect.width >= 32 && rect.height >= 32
            && CGRect(origin: .zero, size: viewportSize).contains(rect)
            && scale.isFinite && (0.25...2).contains(scale)
    }

    func surfaceFrame(in bounds: CGRect) -> CGRect {
        CGRect(x: -rect.minX * scale, y: -rect.minY * scale,
               width: viewportSize.width * scale, height: viewportSize.height * scale)
    }
}

/// Framing uses the live page's actual position inside its owning window.
struct FloatingRegionSelection: Identifiable {
    let id = UUID()
    let tab: Tab
    let pageFrame: CGRect
    let viewportSize: CGSize
    let documentRevision: UUID

    /// Keeps drawing coordinates finite even when a drag begins outside the page.
    func boundedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        let first = CGPoint(x: start.x.clamped(to: 0...viewportSize.width), y: start.y.clamped(to: 0...viewportSize.height))
        let last = CGPoint(x: end.x.clamped(to: 0...viewportSize.width), y: end.y.clamped(to: 0...viewportSize.height))
        return CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                      width: abs(last.x - first.x), height: abs(last.y - first.y))
    }
}
