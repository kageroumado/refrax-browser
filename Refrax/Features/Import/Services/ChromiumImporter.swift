import Foundation

/// Imports bookmarks from Chromium-based browsers.
///
/// Chromium browsers (Chrome, Brave, Edge, Opera, Vivaldi) store bookmarks
/// in a JSON file named `Bookmarks` within each profile directory.
///
/// ## File Format
///
/// The Chromium bookmarks file follows this structure:
///
/// ```json
/// {
///   "roots": {
///     "bookmark_bar": {
///       "name": "Bookmarks bar",
///       "children": [...]
///     },
///     "other": {
///       "name": "Other bookmarks",
///       "children": [...]
///     },
///     "synced": {
///       "name": "Mobile bookmarks",
///       "children": [...]
///     }
///   }
/// }
/// ```
///
/// Each bookmark entry has:
/// - `type`: Either `"url"` for bookmarks or `"folder"` for folders
/// - `name`: Display title
/// - `url`: Web address (only for `type: "url"`)
/// - `date_added`: Creation timestamp in Windows FILETIME format
/// - `children`: Array of nested items (only for `type: "folder"`)
///
/// ## Date Format
///
/// Chromium uses Windows FILETIME format: microseconds since January 1, 1601.
/// This is converted to Unix timestamp using the epoch offset.
///
/// ## Supported Browsers
///
/// - Google Chrome (all channels)
/// - Microsoft Edge
/// - Brave Browser
/// - Opera
/// - Vivaldi
final class ChromiumImporter: DataImporter, Sendable {
    let browser: ThirdPartyBrowser

    init(browser: ThirdPartyBrowser) {
        self.browser = browser
    }

    func canImport(from profile: BrowserProfile) -> Bool {
        let bookmarksFile = profile.path.appendingPathComponent("Bookmarks")
        return FileManager.default.fileExists(atPath: bookmarksFile.path)
    }

    func importBookmarks(from profile: BrowserProfile) async throws -> [ImportedFolder] {
        let bookmarksFile = profile.path.appendingPathComponent("Bookmarks")

        guard FileManager.default.fileExists(atPath: bookmarksFile.path) else {
            throw ImportError.fileNotFound(bookmarksFile.path)
        }

        let data = try Data(contentsOf: bookmarksFile)
        let json = try parseJSON(data: data)
        let roots = try extractRoots(from: json)

        return parseRootFolders(roots)
    }
}

// MARK: - JSON Parsing

private extension ChromiumImporter {
    func parseJSON(data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.parseError("Invalid JSON structure")
        }
        return json
    }

    func extractRoots(from json: [String: Any]) throws -> [String: Any] {
        guard let roots = json["roots"] as? [String: Any] else {
            throw ImportError.parseError("Missing 'roots' key in Chromium bookmarks")
        }
        return roots
    }

    func parseRootFolders(_ roots: [String: Any]) -> [ImportedFolder] {
        var folders: [ImportedFolder] = []

        if let bookmarkBar = roots["bookmark_bar"] as? [String: Any] {
            if let folder = parseFolder(bookmarkBar, path: []) {
                folders.append(folder)
            }
        }

        if let other = roots["other"] as? [String: Any] {
            if let folder = parseFolder(other, path: []) {
                folders.append(folder)
            }
        }

        if let synced = roots["synced"] as? [String: Any] {
            if let folder = parseFolder(synced, path: []) {
                folders.append(folder)
            }
        }

        return folders
    }
}

// MARK: - Folder and Bookmark Parsing

private extension ChromiumImporter {
    func parseFolder(_ dict: [String: Any], path: [String]) -> ImportedFolder? {
        let name = dict["name"] as? String ?? "Untitled"
        let currentPath = path + [name]

        guard let children = dict["children"] as? [[String: Any]] else {
            return ImportedFolder(name: name, path: path, bookmarks: [], subfolders: [])
        }

        var bookmarks: [ImportedBookmark] = []
        var subfolders: [ImportedFolder] = []

        for child in children {
            let itemType = child["type"] as? String

            if itemType == "url" {
                if let bookmark = parseBookmark(child, folderPath: currentPath) {
                    bookmarks.append(bookmark)
                }
            } else if itemType == "folder" {
                if let subfolder = parseFolder(child, path: currentPath) {
                    subfolders.append(subfolder)
                }
            }
        }

        return ImportedFolder(
            name: name,
            path: path,
            bookmarks: bookmarks,
            subfolders: subfolders,
        )
    }

    func parseBookmark(_ dict: [String: Any], folderPath: [String]) -> ImportedBookmark? {
        guard
            let urlString = dict["url"] as? String,
            let url = URL(string: urlString)
        else {
            return nil
        }

        let title = dict["name"] as? String ?? urlString
        let dateAdded = parseChromiumDate(dict["date_added"])

        return ImportedBookmark(
            url: url,
            title: title,
            dateAdded: dateAdded,
            folderPath: folderPath,
        )
    }

    /// Converts a Chromium date string to a Swift Date.
    ///
    /// Chromium stores dates as strings representing microseconds since
    /// the Windows FILETIME epoch (January 1, 1601 UTC).
    ///
    /// The offset between Windows epoch (1601) and Unix epoch (1970) is 11,644,473,600 seconds.
    ///
    /// - SeeAlso: [FILETIME structure](https://learn.microsoft.com/en-us/windows/win32/api/minwinbase/ns-minwinbase-filetime)
    func parseChromiumDate(_ value: Any?) -> Date? {
        guard
            let dateString = value as? String,
            let microseconds = Int64(dateString)
        else {
            return nil
        }

        let windowsToUnixEpochOffset: TimeInterval = 11_644_473_600
        let seconds = Double(microseconds) / 1_000_000
        return Date(timeIntervalSince1970: seconds - windowsToUnixEpochOffset)
    }
}
