import Foundation

// MARK: - Zoom Control

extension WebPage {
    /// Applies a zoom level, in percent, through whichever engine renders the page.
    func setZoom(_ zoom: Int) {
        let clampedZoom = max(50, min(300, zoom))
        currentZoom = clampedZoom
        let factor = Double(clampedZoom) / 100.0
        if let enginePage {
            enginePage.perform(.setZoom(factor: factor))
        } else {
            backingWebView.pageZoom = factor
        }
    }

    /// The page zoom as a multiplier, 1.0 being 100%.
    var zoomFactor: Double {
        enginePage == nil ? backingWebView.pageZoom : state.zoom
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
