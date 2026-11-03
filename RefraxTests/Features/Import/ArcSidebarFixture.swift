import Foundation
@testable import Refrax

/// Builds `StorableSidebar.json` in Arc's own shape: keyed collections as flat arrays that
/// alternate key and value, items linked by `parentID` and `childrenIds`, each space pointing
/// to its pinned and unpinned containers. Every title and address is made up.
struct ArcSidebarFixture {
    /// A row of the sidebar.
    indirect enum Row {
        case tab(String, String)
        case folder(String, [Row])
        /// A split view: a container of tabs without a title.
        case split([Row])
        /// An item with no address, like an Arc note.
        case note
    }

    struct SpaceSpec {
        var id = UUID().uuidString
        var title: String?
        var emoji: String?
        var color: (red: Double, green: Double, blue: Double)?
        var isDefaultProfile = true
        var pinned: [Row] = []
        var unpinned: [Row] = []
    }

    var spaces: [SpaceSpec] = []
    var favorites: [Row] = []

    private var items: [Any] = []

    func json() throws -> Data {
        var builder = self
        var spaceList: [Any] = []
        for space in spaces {
            let pinnedID = builder.container(type: ["spaceItems": ["_0": space.id]], rows: space.pinned)
            let unpinnedID = builder.container(type: ["spaceItems": ["_0": space.id]], rows: space.unpinned)
            var object: [String: Any] = [
                "id": space.id,
                "profile": space.isDefaultProfile ? ["default": true] : ["custom": ["_0": ["directoryBasename": "Profile 1"]]],
                "newContainerIDs": [["unpinned": ["_0": ["shared": [:]]]], unpinnedID, ["pinned": [:]], pinnedID],
                "containerIDs": ["pinned", pinnedID, "unpinned", unpinnedID],
            ]
            if let title = space.title {
                object["title"] = title
            }
            var customInfo: [String: Any] = [:]
            if let emoji = space.emoji {
                customInfo["iconType"] = ["emoji_v2": emoji]
            }
            if let color = space.color {
                customInfo["windowTheme"] = [
                    "primaryColorPalette": [
                        "midTone": ["red": color.red, "green": color.green, "blue": color.blue, "alpha": 1, "colorSpace": "extendedSRGB"],
                    ],
                ]
            }
            object["customInfo"] = customInfo
            spaceList.append(space.id)
            spaceList.append(object)
        }
        let topAppsID = builder.container(type: ["topApps": ["_0": ["default": true]]], rows: favorites)
        let root: [String: Any] = [
            "sidebar": [
                "containers": [
                    ["global": [:]],
                    ["spaces": spaceList, "items": builder.items, "topAppsContainerIDs": [["default": true], topAppsID]],
                ],
            ],
            "version": 1,
        ]
        return try JSONSerialization.data(withJSONObject: root)
    }

    /// Writes the sidebar into a temporary Arc folder and returns the Chromium profile inside
    /// it, the folder ``BrowserDetector`` reports.
    func writeProfile() throws -> (profile: BrowserProfile, cleanup: () -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("arc-fixture-\(UUID().uuidString)")
        let profileFolder = root.appendingPathComponent("User Data/Default")
        try FileManager.default.createDirectory(at: profileFolder, withIntermediateDirectories: true)
        try json().write(to: root.appendingPathComponent("StorableSidebar.json"))
        let profile = BrowserProfile(id: "default", name: "Default", path: profileFolder, browser: .arc)
        return (profile, { try? FileManager.default.removeItem(at: root) })
    }

    // MARK: Items

    private mutating func container(type: [String: Any], rows: [Row]) -> String {
        let id = UUID().uuidString
        let children = rows.map { add($0, parentID: id) }
        append([
            "id": id,
            "parentID": NSNull(),
            "childrenIds": children,
            "data": ["itemContainer": ["containerType": type]],
            "title": NSNull(),
            "createdAt": 0,
        ])
        return id
    }

    private mutating func add(_ row: Row, parentID: String) -> String {
        let id = UUID().uuidString
        switch row {
        case let .tab(title, url):
            append([
                "id": id, "parentID": parentID, "childrenIds": [], "title": title,
                "data": ["tab": ["savedURL": url, "savedTitle": title, "savedMuteStatus": "allowAudio"]],
            ])
        case let .folder(title, rows):
            let children = rows.map { add($0, parentID: id) }
            append(["id": id, "parentID": parentID, "childrenIds": children, "title": title, "data": ["list": [:]]])
        case let .split(rows):
            let children = rows.map { add($0, parentID: id) }
            append([
                "id": id, "parentID": parentID, "childrenIds": children, "title": NSNull(),
                "data": ["splitView": ["layoutOrientation": "horizontal"]],
            ])
        case .note:
            append(["id": id, "parentID": parentID, "childrenIds": [], "title": "Note", "data": ["arcDocument": ["arcDocumentID": id]]])
        }
        return id
    }

    private mutating func append(_ item: [String: Any]) {
        items.append(item["id"]!)
        items.append(item)
    }
}
