import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// On-disk cache of page renders, one JPEG per tab, so a slab or a card has a picture of a
/// page across relaunch and eviction.
/// Files are named by tab id under `Canvas/Snapshots` in app storage.
nonisolated enum CanvasSnapshotStore {
    private static let directory: URL = Directories.appStorage
        .appendingPathComponent("Canvas", isDirectory: true)
        .appendingPathComponent("Snapshots", isDirectory: true)

    private static let compressionFactor = 0.8

    private static func url(for tabID: UUID) -> URL {
        directory.appendingPathComponent("\(tabID.uuidString).jpg")
    }

    /// Writes a render for a tab from its image, encoding off the main actor: the image is
    /// handed over as it is, with no copy of its pixels made first.
    static func save(image: CGImage, for tabID: UUID) async {
        let target = url(for: tabID)
        await Task.detached(priority: .utility) {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: compressionFactor] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? (data as Data).write(to: target, options: .atomic)
        }.value
    }

    /// Reads the stored snapshot bytes for a tab, if any.
    static func load(for tabID: UUID) async -> Data? {
        let source = url(for: tabID)
        return await Task.detached(priority: .utility) {
            try? Data(contentsOf: source)
        }.value
    }

    /// Deletes stored snapshots whose tab no longer exists.
    static func prune(keeping tabIDs: Set<UUID>) async {
        await Task.detached(priority: .background) {
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
            for file in files {
                let name = file.deletingPathExtension().lastPathComponent
                if let id = UUID(uuidString: name), !tabIDs.contains(id) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }.value
    }
}
