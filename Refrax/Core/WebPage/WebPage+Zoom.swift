import Foundation

// MARK: - Zoom Control

extension WebPage {
    /// Applies a zoom level to the page using WKWebView.pageZoom.
    func setZoom(_ zoom: Int) {
        let clampedZoom = max(50, min(300, zoom))
        currentZoom = clampedZoom
        backingWebView.pageZoom = Double(clampedZoom) / 100.0
    }

    /// Increases zoom level to the next standard value.
    func zoomIn() {
        let levels = Constants.AddressBar.zoomLevels
        let currentIndex = levels.firstIndex(where: { $0 >= currentZoom }) ?? levels.count - 1
        let nextIndex = min(currentIndex + 1, levels.count - 1)
        setZoom(levels[nextIndex])
    }

    /// Decreases zoom level to the previous standard value.
    func zoomOut() {
        let levels = Constants.AddressBar.zoomLevels
        let currentIndex = levels.lastIndex(where: { $0 <= currentZoom }) ?? 0
        let prevIndex = max(currentIndex - 1, 0)
        setZoom(levels[prevIndex])
    }

    /// Resets zoom level to 100%.
    func resetZoom() {
        setZoom(100)
    }
}
