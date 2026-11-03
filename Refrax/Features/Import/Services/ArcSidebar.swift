import Foundation
import SwiftUI

/// The organization read from Arc's sidebar: its spaces, their folders and tabs, and the
/// favorites shown above every space.
///
/// ``ArcSidebar/load(from:)`` reads it from a profile; ``ArcSpaceImporter`` turns it into
/// Refrax spaces, islands, and favorites.
nonisolated struct ArcSidebar: Sendable, Equatable {
    /// The spaces, in Arc's order.
    var spaces: [Space]

    /// The favorites, in Arc's order.
    var favorites: [Tab]

    /// An Arc space.
    struct Space: Sendable, Equatable {
        /// Arc's identifier for the space, stable across exports.
        var id: String

        /// The space's name, or `nil` for one Arc shows unnamed.
        var title: String?

        /// The emoji Arc shows for the space, if it has one.
        var emoji: String?

        /// The space's theme color, Arc's mid tone of its primary palette.
        var color: Color.Components?

        /// Whether the space belongs to Arc's default profile. Spaces of other profiles keep
        /// their own website data in Arc.
        var isInDefaultProfile: Bool

        /// The pinned section: tabs and folders kept above the divider.
        var pinned: [Item]

        /// The tabs below the divider, which Arc archives after a while.
        var unpinned: [Item]
    }

    /// A row of Arc's sidebar.
    enum Item: Sendable, Equatable {
        case tab(Tab)
        case folder(Folder)
    }

    /// A saved tab: its address and the title Arc shows.
    struct Tab: Sendable, Equatable {
        var url: URL
        var title: String
    }

    /// A folder of tabs and folders.
    struct Folder: Sendable, Equatable {
        var title: String
        var items: [Item]
    }
}

// MARK: - Loading

nonisolated extension ArcSidebar {
    /// The sidebar file's name.
    static let fileName = "StorableSidebar.json"

    /// Finds the sidebar file of an Arc profile.
    ///
    /// Arc keeps it in its support folder, two levels above the Chromium profile
    /// (`Arc/User Data/Default`) that ``BrowserDetector`` reports, so the profile's folder
    /// and its two parents are searched.
    static func sidebarFile(for profile: BrowserProfile) -> URL? {
        var folder = profile.path
        for _ in 0 ..< 3 {
            let candidate = folder.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            folder.deleteLastPathComponent()
        }
        return nil
    }

    /// Reads the sidebar of an Arc profile, off the main actor.
    ///
    /// - Throws: ``ImportError/fileNotFound(_:)`` when the profile has no sidebar file,
    ///   ``ImportError/parseError(_:)`` when the file is not Arc's sidebar format.
    @concurrent
    static func load(from profile: BrowserProfile) async throws -> ArcSidebar {
        guard let file = sidebarFile(for: profile) else {
            throw ImportError.fileNotFound(profile.path.appendingPathComponent(fileName).path)
        }
        return try parse(Data(contentsOf: file))
    }

    /// Parses the contents of `StorableSidebar.json`.
    ///
    /// The file keeps keyed collections as flat arrays that alternate key and value
    /// (`["pinned", "<id>", "unpinned", "<id>"]`, `["<id>", {item}, …]`). Items point to their
    /// parent with `parentID` and list their children in `childrenIds`.
    ///
    /// - Throws: ``ImportError/parseError(_:)`` when the data is not Arc's sidebar format.
    static func parse(_ data: Data) throws -> ArcSidebar {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.parseError("\(fileName) is not a JSON object")
        }
        guard
            let sidebar = json["sidebar"] as? [String: Any],
            let containers = sidebar["containers"] as? [Any]
        else {
            throw ImportError.parseError("Missing 'sidebar.containers' in Arc data")
        }
        guard let container = containers.lazy.compactMap({ $0 as? [String: Any] }).first(where: { $0["spaces"] != nil })
        else {
            throw ImportError.parseError("Arc data holds no spaces")
        }
        return SidebarReader(container: container).sidebar()
    }
}

// MARK: - Reading

/// Walks one sidebar container: its spaces and the item tree they point into.
private nonisolated struct SidebarReader {
    private let spaces: [[String: Any]]
    private let items: [String: [String: Any]]
    private let childrenByParent: [String: [String]]

    init(container: [String: Any]) {
        self.spaces = Self.objects(in: container["spaces"])
        let items = Self.objects(in: container["items"])
        var index: [String: [String: Any]] = [:]
        var childrenByParent: [String: [String]] = [:]
        for item in items {
            guard let id = item["id"] as? String else { continue }
            index[id] = item
            if let parentID = item["parentID"] as? String {
                childrenByParent[parentID, default: []].append(id)
            }
        }
        self.items = index
        self.childrenByParent = childrenByParent
    }

    func sidebar() -> ArcSidebar {
        let spaces = spaces.enumerated().compactMap { index, space in self.space(space, index: index) }
        var seen: Set<URL> = []
        let favorites = favoriteContainerIDs().flatMap { tabs(in: rows(under: $0, visited: [])) }
            .filter { seen.insert($0.url).inserted }
        return ArcSidebar(spaces: spaces, favorites: favorites)
    }

    private func space(_ space: [String: Any], index: Int) -> ArcSidebar.Space? {
        guard let id = space["id"] as? String else { return nil }
        let containers = Self.containerIDs(of: space)
        let customInfo = space["customInfo"] as? [String: Any]
        let profile = space["profile"] as? [String: Any]
        let title = (space["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ArcSidebar.Space(
            id: id,
            title: title?.isEmpty == false ? title : nil,
            emoji: Self.emoji(in: customInfo?["iconType"]),
            color: Self.themeColor(in: customInfo),
            isInDefaultProfile: profile == nil || profile?["default"] != nil,
            pinned: containers.pinned.map { rows(under: $0, visited: []) } ?? [],
            unpinned: containers.unpinned.map { rows(under: $0, visited: []) } ?? [],
        )
    }

    /// The rows under an item or container, in sidebar order.
    ///
    /// The parent's `childrenIds` give the order; children that name the parent but are
    /// missing from that list follow. Items that only hold others (a split view) give their
    /// children in their place, and items without an address (notes, easels) are left out.
    private func rows(under parentID: String, visited: Set<String>) -> [ArcSidebar.Item] {
        guard !visited.contains(parentID) else { return [] }
        let visited = visited.union([parentID])
        let listed = (items[parentID]?["childrenIds"] as? [String]) ?? []
        let listedSet = Set(listed)
        let unlisted = (childrenByParent[parentID] ?? []).filter { !listedSet.contains($0) }
        return (listed + unlisted).compactMap { items[$0] }.flatMap { row($0, visited: visited) }
    }

    private func row(_ item: [String: Any], visited: Set<String>) -> [ArcSidebar.Item] {
        guard let id = item["id"] as? String else { return [] }
        let data = item["data"] as? [String: Any] ?? [:]
        if let tab = data["tab"] as? [String: Any] {
            return self.tab(item, tab: tab).map { [.tab($0)] } ?? []
        }
        let children = rows(under: id, visited: visited)
        if data["list"] != nil {
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return [.folder(ArcSidebar.Folder(title: title.isEmpty ? "Untitled Folder" : title, items: children))]
        }
        return children
    }

    private func tab(_ item: [String: Any], tab: [String: Any]) -> ArcSidebar.Tab? {
        guard let saved = tab["savedURL"] as? String, let url = Self.address(saved) else { return nil }
        let candidates = [item["title"] as? String, tab["savedTitle"] as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        let title = candidates.first { !$0.isEmpty } ?? url.host ?? url.absoluteString
        return ArcSidebar.Tab(url: url, title: title)
    }

    private func tabs(in rows: [ArcSidebar.Item]) -> [ArcSidebar.Tab] {
        rows.flatMap { row -> [ArcSidebar.Tab] in
            switch row {
            case let .tab(tab): [tab]
            case let .folder(folder): tabs(in: folder.items)
            }
        }
    }

    /// The containers of Arc's favorites: those of the default profile first.
    private func favoriteContainerIDs() -> [String] {
        let containers = items.values.compactMap { item -> (id: String, isDefault: Bool, created: Double)? in
            guard
                let id = item["id"] as? String,
                let container = (item["data"] as? [String: Any])?["itemContainer"] as? [String: Any],
                let type = container["containerType"] as? [String: Any],
                let topApps = type["topApps"] as? [String: Any]
            else { return nil }
            let profile = topApps["_0"] as? [String: Any]
            return (id, profile == nil || profile?["default"] != nil, item["createdAt"] as? Double ?? 0)
        }
        return containers.sorted { ($0.isDefault ? 0 : 1, $0.created) < ($1.isDefault ? 0 : 1, $1.created) }.map(\.id)
    }

    // MARK: Values

    /// The objects of a flat key-value array, in order.
    private static func objects(in value: Any?) -> [[String: Any]] {
        (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    /// A space's pinned and unpinned container IDs, from `newContainerIDs` (keys are
    /// single-key objects) or the older `containerIDs` (keys are strings).
    private static func containerIDs(of space: [String: Any]) -> (pinned: String?, unpinned: String?) {
        var pinned: String?
        var unpinned: String?
        for key in ["newContainerIDs", "containerIDs"] {
            guard let list = space[key] as? [Any] else { continue }
            for index in stride(from: 0, to: list.count - 1, by: 2) {
                let kind = (list[index] as? String) ?? (list[index] as? [String: Any])?.keys.first
                guard let id = list[index + 1] as? String else { continue }
                switch kind {
                case "pinned": pinned = pinned ?? id
                case "unpinned": unpinned = unpinned ?? id
                default: break
                }
            }
        }
        return (pinned, unpinned)
    }

    /// The emoji of a space's `iconType`: `{"emoji_v2": "🌿"}`, or `{"emoji": …}` as a string
    /// or a code point. Arc's own symbols have no SF Symbol counterpart and read as `nil`.
    private static func emoji(in iconType: Any?) -> String? {
        guard let icon = iconType as? [String: Any] else { return nil }
        let text: String? = if let string = (icon["emoji_v2"] ?? icon["emoji"]) as? String {
            string
        } else if let code = icon["emoji"] as? Int, let scalar = Unicode.Scalar(code) {
            String(Character(scalar))
        } else {
            nil
        }
        guard let text, text.count == 1, text.unicodeScalars.contains(where: \.properties.isEmoji) else { return nil }
        return text
    }

    /// The mid tone of a space's primary palette.
    private static func themeColor(in customInfo: [String: Any]?) -> Color.Components? {
        guard
            let theme = customInfo?["windowTheme"] as? [String: Any],
            let palette = theme["primaryColorPalette"] as? [String: Any],
            let tone = palette["midTone"] as? [String: Any],
            let red = (tone["red"] as? NSNumber)?.doubleValue,
            let green = (tone["green"] as? NSNumber)?.doubleValue,
            let blue = (tone["blue"] as? NSNumber)?.doubleValue
        else { return nil }
        let space = (tone["colorSpace"] as? String)?.lowercased() ?? ""
        func clamped(_ value: Double) -> Double { min(max(value, 0), 1) }
        return Color.Components(
            red: clamped(red), green: clamped(green), blue: clamped(blue),
            colorSpace: space.contains("p3") ? .displayP3 : .sRGB,
        )
    }

    /// An address worth a tab: http, https, or a file. Arc escapes slashes in some exports.
    private static func address(_ string: String) -> URL? {
        let cleaned = string
            .replacingOccurrences(of: "\\/", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleaned), let scheme = url.scheme?.lowercased(),
              ["http", "https", "file"].contains(scheme)
        else { return nil }
        return url
    }
}
