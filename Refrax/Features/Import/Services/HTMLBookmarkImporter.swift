import Foundation

/// Imports bookmarks from Netscape HTML bookmark files.
///
/// The Netscape HTML bookmark format is the universal interchange format
/// supported by all major browsers for exporting and importing bookmarks.
///
/// ## File Format
///
/// The format uses HTML definition lists (`<DL>`) to represent hierarchy:
///
/// ```html
/// <!DOCTYPE NETSCAPE-Bookmark-file-1>
/// <TITLE>Bookmarks</TITLE>
/// <H1>Bookmarks</H1>
/// <DL><p>
///     <DT><H3 ADD_DATE="1234567890">Folder Name</H3>
///     <DL><p>
///         <DT><A HREF="https://..." ADD_DATE="1234567890">Title</A>
///     </DL><p>
/// </DL><p>
/// ```
///
/// ## Elements
///
/// - `<DT><H3>`: Folder header (may have `ADD_DATE`, `LAST_MODIFIED` attributes)
/// - `<DT><A>`: Bookmark link (has `HREF`, may have `ADD_DATE`, `ICON` attributes)
/// - `<DL>`: Contains child items of the preceding folder
/// - `<DD>`: Optional description (not imported)
///
/// ## Date Format
///
/// Dates are Unix timestamps (seconds since January 1, 1970).
///
/// ## Usage
///
/// ```swift
/// let importer = HTMLBookmarkImporter()
/// let folders = try await importer.importBookmarks(from: fileURL)
/// ```
///
/// - SeeAlso: [Netscape Bookmark File Format](https://docs.fileformat.com/web/html/#bookmark-file-format)
final class HTMLBookmarkImporter: Sendable {
    /// Imports bookmarks from an HTML file at the specified URL.
    ///
    /// - Parameter url: URL of the HTML bookmarks file.
    /// - Returns: Array of root-level folders containing all bookmarks.
    /// - Throws: `ImportError` if the file cannot be read or parsed.
    func importBookmarks(from url: URL) async throws -> [ImportedFolder] {
        let html = try loadHTMLFile(url)
        let document = try parseHTML(html)

        guard let rootElement = document.rootElement() else {
            throw ImportError.parseError("No root element found in HTML document")
        }

        // Safari exports have H3 elements at the body level (siblings of DL),
        // while Chrome/Firefox have a wrapper DL containing folder DD elements.
        // Detect and handle both formats.
        if let safariResult = try parseSafariFormat(in: rootElement), !safariResult.isEmpty {
            return safariResult
        }

        let dlElement = try findMainDefinitionList(in: rootElement)
        return parseDefinitionList(dlElement, path: [])
    }
}

// MARK: - File Loading and Parsing

private extension HTMLBookmarkImporter {
    func loadHTMLFile(_ url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            do {
                return try String(contentsOf: url, encoding: .isoLatin1)
            } catch {
                throw ImportError.permissionDenied(url.path)
            }
        }
    }

    func parseHTML(_ html: String) throws -> XMLDocument {
        guard let data = html.data(using: .utf8) else {
            throw ImportError.parseError("Failed to encode HTML as UTF-8 data")
        }

        let options: XMLNode.Options = [.documentTidyHTML, .nodePreserveWhitespace]

        do {
            return try XMLDocument(data: data, options: options)
        } catch {
            throw ImportError.parseError("Failed to parse HTML: \(error.localizedDescription)")
        }
    }

    func findMainDefinitionList(in root: XMLElement) throws -> XMLElement {
        let dlElements = (try? root.nodes(forXPath: "//dl")) as? [XMLElement] ?? []

        guard let mainDL = dlElements.first else {
            throw ImportError.parseError("No bookmark list (<DL>) found in HTML")
        }

        return mainDL
    }

    /// Attempts to parse Safari's export format where H3 and DL are siblings at the body level.
    ///
    /// Safari exports don't wrap all folders in a container DL. Instead, each folder is
    /// represented as an H3 followed by a sibling DL at the body level:
    ///
    /// ```html
    /// <body>
    ///   <h1>Bookmarks</h1>
    ///   <h3>Favorites</h3>
    ///   <dl>...</dl>
    ///   <h3>Development</h3>
    ///   <dl>...</dl>
    /// </body>
    /// ```
    ///
    /// - Returns: Parsed folders if Safari format is detected, nil otherwise.
    func parseSafariFormat(in root: XMLElement) throws -> [ImportedFolder]? {
        // Find the body element
        guard let body = (try? root.nodes(forXPath: "//body"))?.first as? XMLElement else {
            return nil
        }

        let children = body.children ?? []

        // Check if there are H3 elements as direct children of body
        let h3Elements = children.compactMap { child -> XMLElement? in
            guard let element = child as? XMLElement,
                  element.name?.lowercased() == "h3" else {
                return nil
            }
            return element
        }

        // If no H3 at body level, this isn't Safari format
        guard !h3Elements.isEmpty else {
            return nil
        }

        // Parse each H3 + following DL pair as a folder
        var folders: [ImportedFolder] = []
        var i = 0

        while i < children.count {
            guard let element = children[i] as? XMLElement else {
                i += 1
                continue
            }

            let tagName = element.name?.lowercased() ?? ""

            if tagName == "h3" {
                let folderName = element.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled"
                let isFavoritesFolder = isPersonalToolbarFolder(element) || isFavoritesFolderByName(folderName)

                // Look for the following DL sibling
                var subfolders: [ImportedFolder] = []
                var bookmarks: [ImportedBookmark] = []

                // Find the next DL after this H3
                for j in (i + 1) ..< children.count {
                    guard let nextElement = children[j] as? XMLElement else { continue }
                    let nextTag = nextElement.name?.lowercased() ?? ""

                    if nextTag == "dl" {
                        // Parse the DL contents
                        let parsed = parseDefinitionList(nextElement, path: [folderName])
                        for folder in parsed {
                            if folder.name == "Imported Bookmarks" {
                                bookmarks.append(contentsOf: folder.bookmarks)
                            } else {
                                subfolders.append(folder)
                            }
                        }
                        break
                    } else if nextTag == "h3" {
                        // Next folder starts, this one has no DL
                        break
                    }
                }

                let folder = ImportedFolder(
                    name: folderName,
                    path: [],
                    bookmarks: bookmarks,
                    subfolders: subfolders,
                    isFavoritesFolder: isFavoritesFolder,
                )
                folders.append(folder)
            }

            i += 1
        }

        return folders.isEmpty ? nil : folders
    }
}

// MARK: - Definition List Parsing

private extension HTMLBookmarkImporter {
    func parseDefinitionList(_ dl: XMLElement, path: [String]) -> [ImportedFolder] {
        var folders: [ImportedFolder] = []
        var currentFolder: CurrentFolderState?
        var rootBookmarks: [ImportedBookmark] = []

        let children = dl.children ?? []
        var index = 0

        while index < children.count {
            guard let element = children[index] as? XMLElement else {
                index += 1
                continue
            }

            let result = processElement(
                element,
                path: path,
                currentFolder: &currentFolder,
                rootBookmarks: &rootBookmarks,
            )

            if let completedFolder = result.completedFolder {
                folders.append(completedFolder)
            }

            index += 1 + result.skipCount
        }

        if let folder = currentFolder {
            folders.append(folder.toImportedFolder())
        }

        if !rootBookmarks.isEmpty {
            folders.insert(
                ImportedFolder(
                    name: "Imported Bookmarks",
                    path: path,
                    bookmarks: rootBookmarks,
                    subfolders: [],
                ),
                at: 0,
            )
        }

        return folders
    }

    struct ProcessResult {
        var completedFolder: ImportedFolder?
        var skipCount: Int = 0
    }

    func processElement(
        _ element: XMLElement,
        path: [String],
        currentFolder: inout CurrentFolderState?,
        rootBookmarks: inout [ImportedBookmark],
    ) -> ProcessResult {
        var result = ProcessResult()

        let tagName = element.name?.lowercased() ?? ""

        // XMLDocument's tidy HTML can convert <DT> to <DD> in some cases,
        // so we need to check both element types for folder headers and bookmarks
        if tagName == "dt" || tagName == "dd" {
            result = processDTElement(
                element,
                path: path,
                currentFolder: &currentFolder,
                rootBookmarks: &rootBookmarks,
            )
        } else if tagName == "dl" {
            if var folder = currentFolder {
                let subfolders = parseDefinitionList(element, path: path + [folder.name])
                folder.subfolders.append(contentsOf: subfolders)
                currentFolder = folder
            }
        }

        return result
    }

    func processDTElement(
        _ element: XMLElement,
        path: [String],
        currentFolder: inout CurrentFolderState?,
        rootBookmarks: inout [ImportedBookmark],
    ) -> ProcessResult {
        var result = ProcessResult()

        if let h3 = findElement(named: "h3", in: element) {
            if let folder = currentFolder {
                result.completedFolder = folder.toImportedFolder()
            }

            let folderName = h3.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled"
            let isFavoritesFolder = isPersonalToolbarFolder(h3) || isFavoritesFolderByName(folderName)
            currentFolder = CurrentFolderState(name: folderName, path: path, isFavoritesFolder: isFavoritesFolder)

            // After tidy HTML, the nested <dl> may be inside this element rather than a sibling.
            // When the DL is inside this element, we process it and complete the folder immediately
            // so that subsequent siblings don't get added to this folder.
            if let nestedDL = findElement(named: "dl", in: element) {
                let parsedFolders = parseDefinitionList(nestedDL, path: path + [folderName])
                for folder in parsedFolders {
                    // "Imported Bookmarks" is a synthetic container for root-level bookmarks
                    // These should be added directly to the current folder, not as a subfolder
                    if folder.name == "Imported Bookmarks" {
                        currentFolder?.bookmarks.append(contentsOf: folder.bookmarks)
                    } else {
                        currentFolder?.subfolders.append(folder)
                    }
                }

                // Complete this folder immediately since all its contents came from the nested DL
                result.completedFolder = currentFolder?.toImportedFolder()
                currentFolder = nil
            }
        } else if let anchor = findElement(named: "a", in: element) {
            if let bookmark = parseAnchor(anchor, path: path, currentFolder: currentFolder) {
                if currentFolder != nil {
                    currentFolder?.bookmarks.append(bookmark)
                } else {
                    rootBookmarks.append(bookmark)
                }
            }
        }

        return result
    }
}

// MARK: - Bookmark Parsing

private extension HTMLBookmarkImporter {
    func parseAnchor(_ anchor: XMLElement, path: [String], currentFolder: CurrentFolderState?) -> ImportedBookmark? {
        guard
            let href = anchor.attribute(forName: "href")?.stringValue
            ?? anchor.attribute(forName: "HREF")?.stringValue,
            let url = URL(string: href)
        else {
            return nil
        }

        let title = anchor.stringValue ?? href
        let dateAdded = parseAddDate(from: anchor)

        let folderPath: [String] = if let folder = currentFolder {
            path + [folder.name]
        } else {
            path
        }

        return ImportedBookmark(
            url: url,
            title: title,
            dateAdded: dateAdded,
            folderPath: folderPath,
        )
    }

    func parseAddDate(from element: XMLElement) -> Date? {
        guard
            let addDateString = element.attribute(forName: "add_date")?.stringValue
            ?? element.attribute(forName: "ADD_DATE")?.stringValue,
            let timestamp = Double(addDateString)
        else {
            return nil
        }

        return Date(timeIntervalSince1970: timestamp)
    }
}

// MARK: - Helper Types and Methods

private extension HTMLBookmarkImporter {
    struct CurrentFolderState {
        let name: String
        let path: [String]
        var bookmarks: [ImportedBookmark] = []
        var subfolders: [ImportedFolder] = []
        var isFavoritesFolder: Bool = false

        func toImportedFolder() -> ImportedFolder {
            ImportedFolder(
                name: name,
                path: path,
                bookmarks: bookmarks,
                subfolders: subfolders,
                isFavoritesFolder: isFavoritesFolder,
            )
        }
    }

    func findElement(named name: String, in parent: XMLElement) -> XMLElement? {
        let lowercasedName = name.lowercased()

        for child in parent.children ?? [] {
            guard let element = child as? XMLElement else { continue }

            if element.name?.lowercased() == lowercasedName {
                return element
            }
        }

        return nil
    }

    /// Checks if the H3 element has the PERSONAL_TOOLBAR_FOLDER attribute set to "true".
    ///
    /// This attribute is used by Chrome/Chromium browsers to mark the Bookmarks Bar folder.
    /// The attribute name is case-insensitive.
    func isPersonalToolbarFolder(_ element: XMLElement) -> Bool {
        let attributeValue = element.attribute(forName: "personal_toolbar_folder")?.stringValue
            ?? element.attribute(forName: "PERSONAL_TOOLBAR_FOLDER")?.stringValue
        return attributeValue?.lowercased() == "true"
    }

    /// Checks if the folder name indicates it's a favorites/toolbar folder.
    ///
    /// Safari exports use a folder named "Favorites" without any special attributes.
    /// This check allows those folders to be recognized as favorites folders.
    func isFavoritesFolderByName(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased == "favorites" || lowercased == "bookmarks bar" || lowercased == "bookmarks toolbar"
    }
}
