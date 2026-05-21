#if DEBUG
import Foundation

/// Generates bulk tabs with realistic data for scroll performance testing.
///
/// Creates tabs with varied domains and paths to stress-test the sidebar
/// tab list under load. Favicons are intentionally varied (diverse domains)
/// to exercise all rendering code paths.
enum DebugTabGenerator {
    private static let domains = [
        "google.com", "youtube.com", "facebook.com", "amazon.com", "wikipedia.org",
        "twitter.com", "instagram.com", "linkedin.com", "reddit.com", "netflix.com",
        "apple.com", "microsoft.com", "github.com", "stackoverflow.com", "medium.com",
        "nytimes.com", "bbc.com", "cnn.com", "theguardian.com", "washingtonpost.com",
        "spotify.com", "twitch.tv", "discord.com", "slack.com", "notion.so",
        "figma.com", "dribbble.com", "behance.net", "codepen.io", "vercel.com",
        "stripe.com", "shopify.com", "etsy.com", "ebay.com", "walmart.com",
        "airbnb.com", "booking.com", "tripadvisor.com", "yelp.com", "uber.com",
        "dropbox.com", "trello.com", "asana.com", "jira.atlassian.com", "confluence.atlassian.com",
        "docs.google.com", "sheets.google.com", "drive.google.com", "maps.google.com", "mail.google.com",
    ]

    private static let paths = [
        "home", "dashboard", "settings", "profile", "search",
        "docs", "api", "getting-started", "tutorial",
        "feed", "trending", "explore", "notifications", "messages",
        "products", "cart", "orders", "wishlist",
        "repos", "pulls", "issues", "actions", "projects",
    ]

    /// Generates `count` tabs with realistic varied data.
    static func generate(
        count: Int = 500,
        pinnedRatio: Double = 0.05,
        groupRatio: Double = 0.2,
        tabManager: TabManager,
        groupManager: TabGroupManager,
        space: Space,
    ) {
        let pinnedCount = Int(Double(count) * pinnedRatio)
        let groupedCount = Int(Double(count) * groupRatio)
        let groupSize = 4
        let groupCount = groupedCount / groupSize

        // Pinned tabs
        for i in 0..<pinnedCount {
            let url = makeURL(index: i)
            let tab = tabManager.createTab(url: url, in: space, isPinned: true, makeActive: false)
            tab.activePage.title = "\(paths[i % paths.count].capitalized) - \(domains[i % domains.count])"
        }

        // Grouped tabs
        for g in 0..<groupCount {
            let group = try? groupManager.createGroup(in: space, name: "Group \(g + 1)")
            for j in 0..<groupSize {
                let idx = pinnedCount + g * groupSize + j
                let url = makeURL(index: idx)
                let tab = tabManager.createTab(url: url, in: space, makeActive: false)
                tab.activePage.title = "\(paths[idx % paths.count].capitalized) - \(domains[idx % domains.count])"
                if let group { tab.group = group }
            }
        }

        // Remaining normal tabs
        let remaining = count - pinnedCount - groupedCount
        for i in 0..<remaining {
            let idx = pinnedCount + groupedCount + i
            let url = makeURL(index: idx)
            let tab = tabManager.createTab(url: url, in: space, makeActive: false)
            tab.activePage.title = "\(paths[idx % paths.count].capitalized) - \(domains[idx % domains.count])"
        }
    }

    private static func makeURL(index: Int) -> URL {
        let domain = domains[index % domains.count]
        let path = paths[index % paths.count]
        return URL(string: "https://\(domain)/\(path)/\(index)") ?? .blank
    }
}
#endif
