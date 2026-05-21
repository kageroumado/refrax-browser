import Foundation

/// Imports bookmarks from Arc browser.
///
/// Arc browser stores its sidebar data (including pinned tabs, which function as bookmarks)
/// in a JSON file called `StorableSidebar.json`.
///
/// ## Arc's Bookmark Philosophy
///
/// Arc doesn't use traditional bookmarks. Instead, it has:
/// - **Pinned tabs**: Persistent tabs that function like bookmarks
/// - **Spaces**: Organizational containers (similar to workspaces)
/// - **Folders**: Groups within spaces
///
/// This importer extracts pinned tabs and folders from Arc's sidebar data
/// and converts them to standard bookmark format.
///
/// ## File Format
///
/// The `StorableSidebar.json` file has this structure:
///
/// ```json
/// {
///   "sidebar": {
///     "containers": [
///       null,
///       {
///         "items": [...],
///         "spaces": [...]
///       }
///     ]
///   }
/// }
/// ```
///
/// Each item has:
/// - `id`: Unique identifier
/// - `parentID`: Parent item or container ID
/// - `title`: Optional display name
/// - `data.tab.savedURL`: URL for bookmark items
/// - `data.tab.savedTitle`: Page title
/// - `data.list`: Present for folder items
/// - `childrenIds`: Array of child item IDs
///
/// ## URL Cleaning
///
/// Arc's JSON may contain malformed escape sequences in URLs.
/// This importer cleans URLs by removing invalid escapes.
///
/// - SeeAlso: [Arc Browser](https://arc.net)
final class ArcImporter: DataImporter, Sendable {
    let browser: ThirdPartyBrowser = .arc

    func canImport(from profile: BrowserProfile) -> Bool {
        resolveSidebarFile(from: profile) != nil
    }

    private func resolveSidebarFile(from profile: BrowserProfile) -> URL? {
        let candidates = [
            profile.path.appendingPathComponent("StorableSidebar.json"),
            profile.path.deletingLastPathComponent().appendingPathComponent("StorableSidebar.json"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func importBookmarks(from profile: BrowserProfile) async throws -> [ImportedFolder] {
        let sidebarFile = resolveSidebarFile(from: profile)

        guard let sidebarFile, FileManager.default.fileExists(atPath: sidebarFile.path) else {
            let expectedPath = profile.path.appendingPathComponent("StorableSidebar.json").path
            throw ImportError.fileNotFound(expectedPath)
        }

        let data = try Data(contentsOf: sidebarFile)
        let cleanedData = cleanMalformedJSON(data)
        let json = try parseJSON(data: cleanedData)
        let container = try extractActiveContainer(from: json)

        return parseContainer(container)
    }
}

// MARK: - JSON Parsing

private extension ArcImporter {
    func cleanMalformedJSON(_ data: Data) -> Data {
        guard var jsonString = String(data: data, encoding: .utf8) else {
            return data
        }

        jsonString = jsonString.replacingOccurrences(of: "\\/", with: "/")

        return jsonString.data(using: .utf8) ?? data
    }

    func parseJSON(data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.parseError("Invalid JSON structure in StorableSidebar.json")
        }
        return json
    }

    func extractActiveContainer(from json: [String: Any]) throws -> [String: Any] {
        guard
            let sidebar = json["sidebar"] as? [String: Any],
            let containers = sidebar["containers"] as? [Any?]
        else {
            throw ImportError.parseError("Missing 'sidebar.containers' in Arc data")
        }

        for container in containers {
            if let containerDict = container as? [String: Any],
               let items = containerDict["items"] as? [[String: Any]],
               !items.isEmpty {
                return containerDict
            }
        }

        throw ImportError.noBookmarksFound
    }
}

// MARK: - Container Parsing

private extension ArcImporter {
    func parseContainer(_ container: [String: Any]) -> [ImportedFolder] {
        guard let items = container["items"] as? [[String: Any]] else {
            return []
        }

        let spaces = container["spaces"] as? [[String: Any]] ?? []
        let itemsById = buildItemsIndex(items)

        return parseSpaces(spaces, itemsById: itemsById)
    }

    func buildItemsIndex(_ items: [[String: Any]]) -> [String: [String: Any]] {
        var index: [String: [String: Any]] = [:]
        for item in items {
            if let id = item["id"] as? String {
                index[id] = item
            }
        }
        return index
    }

    func parseSpaces(
        _ spaces: [[String: Any]],
        itemsById: [String: [String: Any]],
    ) -> [ImportedFolder] {
        var folders: [ImportedFolder] = []

        for (index, space) in spaces.enumerated() {
            let spaceName = space["title"] as? String ?? "Space \(index + 1)"
            let pinnedContainerIDs = extractPinnedContainerIDs(from: space)

            let rootItems = findRootItems(
                parentIDs: pinnedContainerIDs,
                itemsById: itemsById,
            )

            var spaceBookmarks: [ImportedBookmark] = []
            var spaceSubfolders: [ImportedFolder] = []

            for rootItem in rootItems {
                parseItem(
                    rootItem,
                    path: [spaceName],
                    itemsById: itemsById,
                    bookmarks: &spaceBookmarks,
                    subfolders: &spaceSubfolders,
                )
            }

            if !spaceBookmarks.isEmpty || !spaceSubfolders.isEmpty {
                folders.append(ImportedFolder(
                    name: spaceName,
                    path: [],
                    bookmarks: spaceBookmarks,
                    subfolders: spaceSubfolders,
                ))
            }
        }

        return folders
    }

    func extractPinnedContainerIDs(from space: [String: Any]) -> Set<String> {
        var containerIDs: Set<String> = []

        if let newContainerIDs = space["newContainerIDs"] as? [[String: String]] {
            for containerIDDict in newContainerIDs {
                if let pinnedID = containerIDDict["pinned"] {
                    containerIDs.insert(pinnedID)
                }
            }
        }

        if let legacyContainerIDs = space["containerIDs"] as? [String] {
            for id in legacyContainerIDs {
                containerIDs.insert(id)
            }
        }

        return containerIDs
    }

    func findRootItems(
        parentIDs: Set<String>,
        itemsById: [String: [String: Any]],
    ) -> [[String: Any]] {
        itemsById.values.filter { item in
            guard let parentID = item["parentID"] as? String else {
                return false
            }
            return parentIDs.contains(parentID)
        }
    }
}

// MARK: - Item Parsing

private extension ArcImporter {
    func parseItem(
        _ item: [String: Any],
        path: [String],
        itemsById: [String: [String: Any]],
        bookmarks: inout [ImportedBookmark],
        subfolders: inout [ImportedFolder],
    ) {
        let data = item["data"] as? [String: Any]
        let isFolder = data?["list"] != nil

        if isFolder {
            if let folder = parseFolder(item, path: path, itemsById: itemsById) {
                subfolders.append(folder)
            }
        } else if let tab = data?["tab"] as? [String: Any] {
            if let bookmark = parseBookmark(item, tab: tab, path: path) {
                bookmarks.append(bookmark)
            }
        }
    }

    func parseFolder(
        _ item: [String: Any],
        path: [String],
        itemsById: [String: [String: Any]],
    ) -> ImportedFolder? {
        let name = item["title"] as? String ?? "Untitled Folder"
        let currentPath = path + [name]
        let itemID = item["id"] as? String ?? ""

        let childIDs = item["childrenIds"] as? [String] ?? []
        let childItems = childIDs.compactMap { itemsById[$0] }

        var bookmarks: [ImportedBookmark] = []
        var subfolders: [ImportedFolder] = []

        for childItem in childItems {
            parseItem(
                childItem,
                path: currentPath,
                itemsById: itemsById,
                bookmarks: &bookmarks,
                subfolders: &subfolders,
            )
        }

        let itemsWithThisParent = itemsById.values.filter {
            ($0["parentID"] as? String) == itemID
        }

        for childItem in itemsWithThisParent {
            let childID = childItem["id"] as? String ?? ""
            guard !childIDs.contains(childID) else { continue }

            parseItem(
                childItem,
                path: currentPath,
                itemsById: itemsById,
                bookmarks: &bookmarks,
                subfolders: &subfolders,
            )
        }

        return ImportedFolder(
            name: name,
            path: path,
            bookmarks: bookmarks,
            subfolders: subfolders,
        )
    }

    func parseBookmark(
        _ item: [String: Any],
        tab: [String: Any],
        path: [String],
    ) -> ImportedBookmark? {
        guard
            let urlString = tab["savedURL"] as? String,
            let url = cleanAndParseURL(urlString)
        else {
            return nil
        }

        let title = item["title"] as? String
            ?? tab["savedTitle"] as? String
            ?? url.host
            ?? urlString

        return ImportedBookmark(
            url: url,
            title: title,
            dateAdded: nil,
            folderPath: path,
        )
    }

    func cleanAndParseURL(_ urlString: String) -> URL? {
        let cleaned = urlString
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return URL(string: cleaned)
    }
}
