import Foundation
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for Arc bookmark import.
    @Tag static var arcImporter: Self
}

// MARK: - ArcImporter Basic Tests

@Suite("ArcImporter Basic", .tags(.arcImporter))
@MainActor
struct ArcImporterBasicTests {
    @Test("Import simple Arc bookmarks")
    func importSimpleBookmarks() async throws {
        let json = createArcSidebarJSON(spaces: [
            ArcSpace(title: "Default Space", items: [
                ArcItem(title: "Example", url: "https://example.com"),
            ]),
        ])

        let (profileURL, cleanup) = try createMockArcProfile(sidebarJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .arc)
        let importer = ArcImporter()

        #expect(importer.canImport(from: profile))

        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders.count == 1)
        #expect(folders[0].name == "Default Space")
        #expect(folders[0].bookmarks.count == 1)
        #expect(folders[0].bookmarks[0].title == "Example")
    }

    @Test("Import multiple spaces")
    func importMultipleSpaces() async throws {
        let json = createArcSidebarJSON(spaces: [
            ArcSpace(title: "Work", items: [
                ArcItem(title: "Work Site", url: "https://work.com"),
            ]),
            ArcSpace(title: "Personal", items: [
                ArcItem(title: "Personal Site", url: "https://personal.com"),
            ]),
        ])

        let (profileURL, cleanup) = try createMockArcProfile(sidebarJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .arc)
        let importer = ArcImporter()
        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders.count == 2)
        let names = Set(folders.map(\.name))
        #expect(names.contains("Work"))
        #expect(names.contains("Personal"))
    }

    @Test("Import folders within space")
    func importFoldersWithinSpace() async throws {
        let json = createArcSidebarJSON(spaces: [
            ArcSpace(title: "Space", items: [
                ArcItem(title: "Regular Tab", url: "https://tab.com"),
            ], folders: [
                ArcFolder(title: "My Folder", items: [
                    ArcItem(title: "Folder Item", url: "https://folder.com"),
                ]),
            ]),
        ])

        let (profileURL, cleanup) = try createMockArcProfile(sidebarJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .arc)
        let importer = ArcImporter()
        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders[0].subfolders.count == 1)
        #expect(folders[0].subfolders[0].name == "My Folder")
        #expect(folders[0].subfolders[0].bookmarks.count == 1)
    }

    @Test("canImport returns false for missing file")
    func canImportReturnsFalseForMissing() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let profile = BrowserProfile(id: "default", name: "Default", path: tempDir, browser: .arc)
        let importer = ArcImporter()

        #expect(!importer.canImport(from: profile))
    }
}

// MARK: - ArcImporter Edge Cases

@Suite("ArcImporter Edge Cases", .tags(.arcImporter))
@MainActor
struct ArcImporterEdgeCaseTests {
    @Test("Handle empty space")
    func handleEmptySpace() async throws {
        let json = createArcSidebarJSON(spaces: [
            ArcSpace(title: "Empty", items: []),
            ArcSpace(title: "HasContent", items: [
                ArcItem(title: "Test", url: "https://test.com"),
            ]),
        ])

        let (profileURL, cleanup) = try createMockArcProfile(sidebarJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .arc)
        let importer = ArcImporter()
        let folders = try await importer.importBookmarks(from: profile)

        // Should only include space with content
        #expect(folders.count == 1)
        #expect(folders[0].name == "HasContent")
    }

    @Test("Handle item without title")
    func handleMissingTitle() async throws {
        let json = createArcSidebarJSON(spaces: [
            ArcSpace(title: "Test", items: [
                ArcItem(title: nil, url: "https://notitle.com", savedTitle: "Saved Title"),
            ]),
        ])

        let (profileURL, cleanup) = try createMockArcProfile(sidebarJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .arc)
        let importer = ArcImporter()
        let folders = try await importer.importBookmarks(from: profile)

        // Should use savedTitle as fallback
        #expect(folders[0].bookmarks[0].title == "Saved Title")
    }

    @Test("Handle escaped slashes in URL")
    func handleEscapedSlashes() async throws {
        let json = createArcSidebarJSON(spaces: [
            ArcSpace(title: "Test", items: [
                ArcItem(title: "Escaped", url: "https:\\/\\/example.com\\/path"),
            ]),
        ])

        let (profileURL, cleanup) = try createMockArcProfile(sidebarJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .arc)
        let importer = ArcImporter()
        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders[0].bookmarks[0].url.absoluteString == "https://example.com/path")
    }

    @Test("Handle invalid URLs")
    func handleInvalidUrls() async throws {
        let json = createArcSidebarJSON(spaces: [
            ArcSpace(title: "Test", items: [
                ArcItem(title: "Valid", url: "https://valid.com"),
                ArcItem(title: "Invalid", url: ""),
            ]),
        ])

        let (profileURL, cleanup) = try createMockArcProfile(sidebarJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .arc)
        let importer = ArcImporter()
        let folders = try await importer.importBookmarks(from: profile)

        // Should only have valid bookmark
        #expect(folders[0].bookmarks.count == 1)
    }

    @Test("Handle Unicode content")
    func handleUnicode() async throws {
        let json = createArcSidebarJSON(spaces: [
            ArcSpace(title: "日本語スペース", items: [
                ArcItem(title: "中文网站", url: "https://example.com"),
                ArcItem(title: "Emoji 🎉", url: "https://emoji.com"),
            ]),
        ])

        let (profileURL, cleanup) = try createMockArcProfile(sidebarJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .arc)
        let importer = ArcImporter()
        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders[0].name == "日本語スペース")
        #expect(folders[0].bookmarks.count == 2)
    }

    @Test("Handle nested folders")
    func handleNestedFolders() async throws {
        let json = createArcSidebarJSON(spaces: [
            ArcSpace(title: "Space", items: [], folders: [
                ArcFolder(title: "Parent", items: [], subfolders: [
                    ArcFolder(title: "Child", items: [
                        ArcItem(title: "Deep", url: "https://deep.com"),
                    ]),
                ]),
            ]),
        ])

        let (profileURL, cleanup) = try createMockArcProfile(sidebarJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .arc)
        let importer = ArcImporter()
        let folders = try await importer.importBookmarks(from: profile)

        let childFolder = folders[0].subfolders[0].subfolders[0]
        #expect(childFolder.name == "Child")
        #expect(childFolder.bookmarks.count == 1)
    }
}

// MARK: - ArcImporter JSON Error Tests

@Suite("ArcImporter Errors", .tags(.arcImporter))
@MainActor
struct ArcImporterErrorTests {
    @Test("Handle invalid JSON")
    func handleInvalidJson() async throws {
        let invalidJSON = "{ this is not valid json }"

        let (profileURL, cleanup) = try createMockArcProfile(rawJSON: invalidJSON)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .arc)
        let importer = ArcImporter()

        // JSON parsing errors come as NSError from JSONSerialization
        await #expect(throws: (any Error).self) {
            _ = try await importer.importBookmarks(from: profile)
        }
    }

    @Test("Handle missing sidebar key")
    func handleMissingSidebar() async throws {
        let json = """
        {
            "version": 1,
            "other_key": {}
        }
        """

        let (profileURL, cleanup) = try createMockArcProfile(rawJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .arc)
        let importer = ArcImporter()

        await #expect(throws: ImportError.self) {
            _ = try await importer.importBookmarks(from: profile)
        }
    }

    @Test("Handle empty containers")
    func handleEmptyContainers() async throws {
        let json = """
        {
            "sidebar": {
                "containers": [null, null]
            }
        }
        """

        let (profileURL, cleanup) = try createMockArcProfile(rawJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .arc)
        let importer = ArcImporter()

        await #expect(throws: ImportError.self) {
            _ = try await importer.importBookmarks(from: profile)
        }
    }
}

// MARK: - Arc JSON Helpers

private struct ArcItem {
    let id: String = UUID().uuidString
    let title: String?
    let url: String
    var savedTitle: String?
}

private struct ArcFolder {
    let id: String = UUID().uuidString
    let title: String
    var items: [ArcItem] = []
    var subfolders: [ArcFolder] = []
}

private struct ArcSpace {
    let title: String
    var items: [ArcItem] = []
    var folders: [ArcFolder] = []
}

private func createArcSidebarJSON(spaces: [ArcSpace]) -> String {
    var itemsList: [[String: Any]] = []
    var spacesList: [[String: Any]] = []

    for (spaceIndex, space) in spaces.enumerated() {
        let pinnedContainerID = "pinned-\(spaceIndex)"

        // Add items from space root
        for item in space.items {
            itemsList.append([
                "id": item.id,
                "parentID": pinnedContainerID,
                "title": item.title as Any,
                "data": [
                    "tab": [
                        "savedURL": item.url,
                        "savedTitle": item.savedTitle ?? item.title as Any,
                    ],
                ],
            ])
        }

        // Add folders
        for folder in space.folders {
            addFolderItems(folder, parentID: pinnedContainerID, itemsList: &itemsList)
        }

        spacesList.append([
            "title": space.title,
            "newContainerIDs": [
                ["pinned": pinnedContainerID],
            ],
        ])
    }

    let container: [String: Any] = [
        "items": itemsList,
        "spaces": spacesList,
    ]

    let sidebar: [String: Any] = [
        "sidebar": [
            "containers": [NSNull(), container],
        ],
    ]

    let data = try! JSONSerialization.data(withJSONObject: sidebar, options: [.prettyPrinted])
    return String(data: data, encoding: .utf8)!
}

private func addFolderItems(_ folder: ArcFolder, parentID: String, itemsList: inout [[String: Any]]) {
    // Add folder item
    var childrenIds: [String] = []

    for item in folder.items {
        childrenIds.append(item.id)
        itemsList.append([
            "id": item.id,
            "parentID": folder.id,
            "title": item.title as Any,
            "data": [
                "tab": [
                    "savedURL": item.url,
                    "savedTitle": item.savedTitle ?? item.title as Any,
                ],
            ],
        ])
    }

    for subfolder in folder.subfolders {
        childrenIds.append(subfolder.id)
        addFolderItems(subfolder, parentID: folder.id, itemsList: &itemsList)
    }

    itemsList.append([
        "id": folder.id,
        "parentID": parentID,
        "title": folder.title,
        "childrenIds": childrenIds,
        "data": [
            "list": [:],
        ],
    ])
}

private func createMockArcProfile(sidebarJSON: String) throws -> (URL, () -> Void) {
    try createMockArcProfile(rawJSON: sidebarJSON)
}

private func createMockArcProfile(rawJSON: String) throws -> (URL, () -> Void) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("arc_test_\(UUID().uuidString)")

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let sidebarFile = tempDir.appendingPathComponent("StorableSidebar.json")
    try rawJSON.write(to: sidebarFile, atomically: true, encoding: .utf8)

    let cleanup: () -> Void = {
        _ = try? FileManager.default.removeItem(at: tempDir)
    }

    return (tempDir, cleanup)
}
