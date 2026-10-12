import AppKit

/// Finds a nearby resting place when browser chrome obscures a page control.
enum ControlIslandAvoidance {
    private static let maximumDisplacement: CGFloat = 160
    private static let clearance: CGFloat = 8

    static func proposedOrigin(for frame: CGRect, in bounds: CGRect, obstacles: [CGRect]) -> CGPoint? {
        let collisions = obstacles.filter { obstacle in
            let visible = obstacle.intersection(bounds)
            guard !visible.isNull, visible.width > 0, visible.height > 0 else { return false }
            let overlap = visible.intersection(frame)
            return !overlap.isNull && overlap.width * overlap.height / (visible.width * visible.height) >= 0.6
        }
        guard !collisions.isEmpty else { return nil }
        let area = bounds.insetBy(dx: ControlIslandPlacement.margin, dy: ControlIslandPlacement.margin)
        let candidates = collisions.flatMap { obstacle in
            [CGPoint(x: frame.minX, y: obstacle.maxY + clearance),
             CGPoint(x: frame.minX, y: obstacle.minY - clearance - frame.height),
             CGPoint(x: obstacle.maxX + clearance, y: frame.minY),
             CGPoint(x: obstacle.minX - clearance - frame.width, y: frame.minY)]
        }
        return candidates.filter { point in
            let candidate = CGRect(origin: point, size: frame.size)
            return area.contains(candidate) && hypot(point.x - frame.minX, point.y - frame.minY) <= maximumDisplacement
                && obstacles.allSatisfy { !$0.insetBy(dx: -clearance, dy: -clearance).intersects(candidate) }
        }.min { hypot($0.x - frame.minX, $0.y - frame.minY) < hypot($1.x - frame.minX, $1.y - frame.minY) }
    }

    /// Samples visible controls once after a page settles, using its desktop viewport.
    static func obstacles(on page: WebPage, in window: NSWindow) async -> [CGRect]? {
        let revision = page.documentRevision
        let script = """
        (() => {
          const active = document.activeElement;
          if (active?.matches('input,textarea,select,[contenteditable="true"]')) return null;
          const selectors = 'button,a[href],input,select,textarea,[role="button"],[role="link"],iframe,canvas';
          const controls = [...document.querySelectorAll(selectors)].slice(0, 2000);
          const rects = [];
          for (const element of controls) {
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
            return CGRect(x: origin.x + rect[0] * scaleX, y: origin.y + rect[1] * scaleY,
                          width: rect[2] * scaleX, height: rect[3] * scaleY)
        }
    }

    private struct Sample: Decodable {
        let width: CGFloat
        let height: CGFloat
        let rects: [[CGFloat]]
    }
}
