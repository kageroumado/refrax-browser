import Foundation

/// What a drop from outside the islands brings: tabs of this browser on their way to another
/// row, or pages to open as new tabs, read from the links, files, and text dropped.
nonisolated struct IslandDropPayload: Equatable, Sendable {
    /// Tabs dragged out of an island, of this window or another: rows to move when they are of
    /// this space, else their addresses open.
    var tabIDs: [UUID] = []
    /// The pages to open, in the order they were dropped, each once.
    var urls: [URL] = []

    /// Reads a drop: the identities of tabs dragged from an island, and the pages to open,
    /// links first, then files (a `.webloc` as the address inside it), and
    /// only when neither brought anything, the addresses written in dropped text.
    ///
    /// Only http and https addresses open from a link, a `.webloc`, or text: a dropped
    /// address is written by whatever app or page it came from, and `javascript:`, `data:`,
    /// `file:`, or an app's own scheme from there would run or reveal something the person
    /// never chose. A file opens as `file://` only when that file itself was dropped.
    ///
    /// - Parameters:
    ///   - tabIDs: Identities of tabs dragged from an island.
    ///   - urls: Every URL on the pasteboard, web and file alike.
    ///   - strings: Plain text on the pasteboard.
    ///   - read: Reads a dropped file's contents, for a `.webloc`.
    init(tabIDs: [UUID] = [], urls: [URL] = [], strings: [String] = [], read: (URL) -> Data? = { try? Data(contentsOf: $0) }) {
        self.tabIDs = tabIDs
        var found: [URL] = []
        for url in urls {
            if url.isFileURL {
                if url.pathExtension.lowercased() == WeblocFile.pathExtension {
                    if let data = read(url), let inside = WeblocFile.url(from: data), inside.isWebURL {
                        found.append(inside)
                    }
                } else if !url.hasDirectoryPath {
                    found.append(url)
                }
            } else if url.isWebURL {
                found.append(url)
            }
        }
        if found.isEmpty {
            found = strings.flatMap(Self.links(in:))
        }
        var seen = Set<URL>()
        self.urls = found.filter { seen.insert($0).inserted }
    }

    var isEmpty: Bool {
        tabIDs.isEmpty && urls.isEmpty
    }

    /// The web addresses written in `text`, a bare domain read as https.
    static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap { match -> URL? in
            guard let url = match.url else { return nil }
            guard url.isWebURL else { return nil }
            // A bare "example.com" is detected as http; pages are asked for securely.
            if url.scheme == "http", let written = Range(match.range, in: text), !text[written].lowercased().hasPrefix("http") {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                components?.scheme = "https"
                return components?.url ?? url
            }
            return url
        }
    }
}
