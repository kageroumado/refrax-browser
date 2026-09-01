import Foundation

/// Decides which tabs a magnet attracts.
///
/// Two tabs are similar when they share a key. The key is the page's host without
/// a leading `www.`; pages without a host (lab pages, data URLs) fall back to the
/// title before a `·` separator, which is how ``CanvasScenario`` names its pages.
/// AI categorization can replace this function without touching the callers.
nonisolated enum CanvasSimilarity {
    static func key(for tab: Tab) -> String? {
        let page = tab.activePage
        if let host = page.url.host(), !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        let title = page.title
        if let separator = title.range(of: " · ") {
            let prefix = title[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
            return prefix.isEmpty ? nil : prefix
        }
        return nil
    }
}
