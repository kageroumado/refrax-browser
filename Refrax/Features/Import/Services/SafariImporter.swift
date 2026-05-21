import Foundation

/// Imports bookmarks from Safari.
///
/// Safari stores bookmarks in a binary property list file called `Bookmarks.plist`
/// located in `~/Library/Safari/`.
///
/// ## File Format
///
/// The plist contains a hierarchical structure:
///
/// ```plist
/// {
///   Children = (
///     {
///       WebBookmarkType = "WebBookmarkTypeList";  // Folder
///       Title = "Favorites";
///       Children = (...);
///     },
///     {
///       WebBookmarkType = "WebBookmarkTypeLeaf";  // Bookmark
///       URLString = "https://...";
///       URIDictionary = { title = "..."; };
///     }
///   );
/// }
/// ```
///
/// ## Bookmark Types
///
/// - `WebBookmarkTypeList`: A folder containing child items
/// - `WebBookmarkTypeLeaf`: An individual bookmark
/// - `WebBookmarkTypeProxy`: Reading list or other special items (skipped)
///
/// ## Permissions
///
/// The Safari bookmarks file requires either:
/// - Full Disk Access granted to Refrax
/// - User explicitly selecting the file via NSOpenPanel
///
/// This importer attempts direct access first, which works if Full Disk Access
/// is enabled or if the app is not sandboxed.
///
/// - SeeAlso: [Safari Bookmarks Format](https://developer.apple.com/documentation/safari-release-notes)
final class SafariImporter: DataImporter, Sendable {
    let browser: ThirdPartyBrowser = .safari

    func canImport(from profile: BrowserProfile) -> Bool {
        let bookmarksPlist = profile.path.appendingPathComponent("Bookmarks.plist")
        return FileManager.default.fileExists(atPath: bookmarksPlist.path)
    }

    func importBookmarks(from profile: BrowserProfile) async throws -> [ImportedFolder] {
        let bookmarksPlist = profile.path.appendingPathComponent("Bookmarks.plist")

        guard FileManager.default.fileExists(atPath: bookmarksPlist.path) else {
            throw ImportError.fileNotFound(bookmarksPlist.path)
        }

        let plist = try loadPlist(from: bookmarksPlist)
        let children = try extractChildren(from: plist)

        return parseChildren(children, path: [])
    }
}

// MARK: - Plist Parsing

private extension SafariImporter {
    func loadPlist(from url: URL) throws -> [String: Any] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.permissionDenied(url.path)
        }

        guard
            let plist = try PropertyListSerialization.propertyList(
                from: data,
                format: nil,
            ) as? [String: Any]
        else {
            throw ImportError.parseError("Invalid Safari bookmarks plist format")
        }

        return plist
    }

    func extractChildren(from plist: [String: Any]) throws -> [[String: Any]] {
        guard let children = plist["Children"] as? [[String: Any]] else {
            throw ImportError.parseError("Missing 'Children' key in Safari bookmarks")
        }
        return children
    }

    func parseChildren(_ children: [[String: Any]], path: [String]) -> [ImportedFolder] {
        var folders: [ImportedFolder] = []

        for child in children {
            let bookmarkType = child["WebBookmarkType"] as? String ?? ""

            switch bookmarkType {
            case "WebBookmarkTypeList":
                if let folder = parseFolder(child, path: path) {
                    folders.append(folder)
                }
            case "WebBookmarkTypeLeaf":
                break
            default:
                break
            }
        }

        return folders
    }
}

// MARK: - Folder and Bookmark Parsing

private extension SafariImporter {
    func parseFolder(_ dict: [String: Any], path: [String]) -> ImportedFolder? {
        let title = extractFolderTitle(from: dict)
        let isSpecial = isSpecialFolder(dict)

        guard let children = dict["Children"] as? [[String: Any]] else {
            return isSpecial ? nil : ImportedFolder(name: title, path: path, bookmarks: [], subfolders: [])
        }

        let (bookmarks, subfolders) = parseFolderChildren(children, parentPath: path + [title])

        if bookmarks.isEmpty, subfolders.isEmpty {
            return nil
        }

        return ImportedFolder(
            name: title,
            path: path,
            bookmarks: bookmarks,
            subfolders: subfolders,
        )
    }

    func parseFolderChildren(
        _ children: [[String: Any]],
        parentPath: [String],
    ) -> (bookmarks: [ImportedBookmark], subfolders: [ImportedFolder]) {
        var bookmarks: [ImportedBookmark] = []
        var subfolders: [ImportedFolder] = []

        for child in children {
            let childType = child["WebBookmarkType"] as? String ?? ""

            if childType == "WebBookmarkTypeLeaf" {
                if let bookmark = parseBookmark(child, folderPath: parentPath) {
                    bookmarks.append(bookmark)
                }
            } else if childType == "WebBookmarkTypeList" {
                if let subfolder = parseFolder(child, path: parentPath) {
                    subfolders.append(subfolder)
                }
            }
        }

        return (bookmarks, subfolders)
    }

    func parseBookmark(_ dict: [String: Any], folderPath: [String]) -> ImportedBookmark? {
        guard
            let urlString = dict["URLString"] as? String,
            let url = URL(string: urlString)
        else {
            return nil
        }

        let title = extractBookmarkTitle(from: dict, fallback: urlString)

        return ImportedBookmark(
            url: url,
            title: title,
            dateAdded: nil,
            folderPath: folderPath,
        )
    }
}

// MARK: - Title Extraction Helpers

private extension SafariImporter {
    func extractFolderTitle(from dict: [String: Any]) -> String {
        if let title = dict["Title"] as? String, !title.isEmpty {
            return title
        }
        return "Untitled"
    }

    func extractBookmarkTitle(from dict: [String: Any], fallback: String) -> String {
        if let uriDict = dict["URIDictionary"] as? [String: Any],
           let title = uriDict["title"] as? String,
           !title.isEmpty {
            return title
        }

        if let title = dict["Title"] as? String, !title.isEmpty {
            return title
        }

        return fallback
    }

    func isSpecialFolder(_ dict: [String: Any]) -> Bool {
        guard let webBookmarkUUID = dict["WebBookmarkUUID"] as? String else {
            return false
        }
        return webBookmarkUUID.contains("Reading")
    }
}
