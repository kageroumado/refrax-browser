import AppKit

/// Finds a nearby resting place when browser chrome obscures a page control.
enum ControlIslandAvoidance {
    private static let maximumDisplacement: CGFloat = 160
    private static let clearance: CGFloat = 8

    static func proposedOrigin(for frame: CGRect, in bounds: CGRect, obstacles: [CGRect]) -> CGPoint? {
        let neighborhood = frame.insetBy(dx: -maximumDisplacement - clearance, dy: -maximumDisplacement - clearance)
        let visible = obstacles.map { $0.intersection(bounds) }
            .filter { !$0.isNull && $0.width > 0 && $0.height > 0 && $0.intersects(neighborhood) }
        guard visible.contains(where: { obstacle in
            let overlap = obstacle.intersection(frame)
            return !overlap.isNull && overlap.width * overlap.height >= obstacle.width * obstacle.height * 0.6
        }) else { return nil }

        let padded = visible.map { $0.insetBy(dx: -clearance, dy: -clearance) }
        let horizontal = padded.filter { $0.minY < frame.maxY && $0.maxY > frame.minY }
            .map { ($0.minX - frame.width) ... $0.maxX }
        let vertical = padded.filter { $0.minX < frame.maxX && $0.maxX > frame.minX }
            .map { ($0.minY - frame.height) ... $0.maxY }
        let candidates = clearBoundaries(around: frame.minX, intervals: horizontal).map { CGPoint(x: $0, y: frame.minY) }
            + clearBoundaries(around: frame.minY, intervals: vertical).map { CGPoint(x: frame.minX, y: $0) }
        let area = bounds.insetBy(dx: ControlIslandPlacement.margin, dy: ControlIslandPlacement.margin)
        return candidates.filter {
            area.contains(CGRect(origin: $0, size: frame.size))
                && hypot($0.x - frame.minX, $0.y - frame.minY) <= maximumDisplacement
        }.min { hypot($0.x - frame.minX, $0.y - frame.minY) < hypot($1.x - frame.minX, $1.y - frame.minY) }
    }

    /// Merging blocked origin ranges finds the nearest clear position on either side in O(n log n).
    private static func clearBoundaries(around position: CGFloat, intervals: [ClosedRange<CGFloat>]) -> [CGFloat] {
        let sorted = intervals.sorted { $0.lowerBound < $1.lowerBound }
        guard var merged = sorted.first else { return [] }
        for interval in sorted.dropFirst() {
            if interval.lowerBound < merged.upperBound {
                merged = merged.lowerBound ... max(merged.upperBound, interval.upperBound)
            } else {
                if merged.lowerBound < position, position < merged.upperBound {
                    break
                }
                merged = interval
            }
        }
        return merged.lowerBound < position && position < merged.upperBound ? [merged.lowerBound, merged.upperBound] : []
    }

    /// Samples visible controls once after a page settles, using its desktop viewport.
    static func obstacles(on page: WebPage, in window: NSWindow) async -> [CGRect]? {
        let revision = page.documentRevision
        let script = """
        (() => {
          const active = document.activeElement;
          if (active?.matches('input,textarea,select,[contenteditable="true"]')) return null;
          const selectors = 'button,a[href],input,select,textarea,[role="button"],[role="link"],iframe,canvas';
          const controls = document.querySelectorAll(selectors);
          const rects = [];
          for (let index = 0; index < Math.min(controls.length, 2000); index++) {
            const element = controls[index];
            const r = element.getBoundingClientRect();
            if (r.width <= 0 || r.height <= 0 || r.right <= 0 || r.bottom <= 0 || r.x >= innerWidth || r.y >= innerHeight) continue;
            const x = Math.max(0, r.x), y = Math.max(0, r.y);
            const width = Math.min(innerWidth, r.right) - x, height = Math.min(innerHeight, r.bottom) - y;
            const hit = document.elementFromPoint(x + width / 2, y + height / 2);
            if (hit && (hit === element || element.contains(hit))) rects.push([x, y, width, height]);
          }
          return JSON.stringify({width: innerWidth, height: innerHeight, rects});
        })()
        """
        guard let raw = try? await page.evaluateJavaScriptWithoutUserGesture(script) as? String,
              let data = raw.data(using: .utf8), let sample = try? JSONDecoder().decode(Sample.self, from: data),
              sample.width > 0, sample.height > 0, revision == page.documentRevision,
              !page.isInFloatingPreview, page.contentView.window === window, let content = window.contentView else { return nil }
        let native = page.contentView.convert(page.contentView.bounds, to: content)
        let origin = CGPoint(x: native.minX, y: content.isFlipped ? native.minY : content.bounds.height - native.maxY)
        let scaleX = native.width / sample.width
        let scaleY = native.height / sample.height
        return sample.rects.compactMap { rect in
            guard rect.count == 4, rect.allSatisfy(\.isFinite) else { return nil }
            return CGRect(
                x: origin.x + rect[0] * scaleX,
                y: origin.y + rect[1] * scaleY,
                width: rect[2] * scaleX,
                height: rect[3] * scaleY,
            )
        }
    }

    private struct Sample: Decodable {
        let width: CGFloat
        let height: CGFloat
        let rects: [[CGFloat]]
    }
}
