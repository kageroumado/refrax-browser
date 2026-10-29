import Foundation

/// Detects document layout changes around a framed element while allowing page scrolling.
enum FloatingRegionAnchor {
    static func capture(_ region: FloatingPageRegion, on page: WebPage) async -> Bool {
        guard region.isValid else { return false }
        let script = """
        (() => {
          const element = document.elementFromPoint(\(region.rect.midX), \(region.rect.midY));
          if (!element) return false;
          const rect = element.getBoundingClientRect();
          globalThis.__refraxKeptRegion = {element: new WeakRef(element), x: rect.x + scrollX,
            y: rect.y + scrollY, width: rect.width, height: rect.height};
          return true;
        })()
        """
        return (try? await page.evaluateJavaScriptWithoutUserGesture(script) as? Bool) == true
    }

    static func remainsValid(on page: WebPage) async -> Bool {
        let script = """
        (() => {
          const anchor = globalThis.__refraxKeptRegion;
          const element = anchor?.element?.deref();
          if (!element?.isConnected) return false;
          const rect = element.getBoundingClientRect();
          return Math.abs(rect.x + scrollX - anchor.x) < 3 && Math.abs(rect.y + scrollY - anchor.y) < 3
            && Math.abs(rect.width - anchor.width) < 3 && Math.abs(rect.height - anchor.height) < 3;
        })()
        """
        return (try? await page.evaluateJavaScriptWithoutUserGesture(script) as? Bool) == true
    }
}
