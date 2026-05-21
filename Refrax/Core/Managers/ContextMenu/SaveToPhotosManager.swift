import AppKit
import Photos

/// Provides authorization checks and menu building for Save to Photos.
///
/// The actual download is handled by `DownloadManager` (which provides cookies,
/// authentication, and progress tracking). This manager handles:
/// - Photos authorization status checks
/// - Album fetching for the context menu submenu
/// - Menu item creation with album choices
///
/// ## Isolation
///
/// This type is `nonisolated` — all Photos framework APIs dispatch to their own
/// internal queues.
nonisolated final class SaveToPhotosManager: Sendable {
    // MARK: - Types

    /// Represents a user album in Photos.
    struct Album: Identifiable, Sendable {
        let id: String
        let title: String
    }

    /// Context for save operations, attached to menu items as `representedObject`.
    struct SaveContext: Sendable {
        let url: URL
        let mediaType: MediaType
        let albumID: String?

        enum MediaType: Sendable {
            case image
            case video
        }
    }

    // MARK: - Authorization

    /// Whether `.addOnly` Photos access is authorized (minimum for "Save to Recents").
    var isPhotosAccessAvailable: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        return status == .authorized || status == .limited
    }

    /// Whether `.readWrite` Photos access is authorized (needed for album listing).
    ///
    /// Checked synchronously — if not already authorized, the album submenu
    /// is simply not shown. No permission prompt is triggered.
    var isAlbumAccessAvailable: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    // MARK: - Menu Item Creation

    /// Creates menu items for saving an image to Photos.
    ///
    /// Returns a "Save Image to Photos" item (saves to Recents), and optionally
    /// a "Save Image to Album..." item with a submenu of user albums.
    func createImageMenuItems(for imageURL: URL, target: AnyObject) -> [NSMenuItem] {
        createMenuItems(
            saveTitle: "Save Image to Photos",
            albumTitle: "Save Image to Album",
            context: SaveContext(url: imageURL, mediaType: .image, albumID: nil),
            target: target,
        )
    }

    /// Creates menu items for saving a video to Photos.
    func createVideoMenuItems(for videoURL: URL, target: AnyObject) -> [NSMenuItem] {
        createMenuItems(
            saveTitle: "Save Video to Photos",
            albumTitle: "Save Video to Album",
            context: SaveContext(url: videoURL, mediaType: .video, albumID: nil),
            target: target,
        )
    }

    private func createMenuItems(
        saveTitle: String,
        albumTitle: String,
        context: SaveContext,
        target: AnyObject,
    ) -> [NSMenuItem] {
        // Direct "Save to Photos" item — always saves to Recents.
        let saveItem = NSMenuItem(
            title: saveTitle,
            action: #selector((any SaveToPhotosTarget).saveToPhotos(_:)),
            keyEquivalent: "",
        )
        saveItem.target = target
        saveItem.representedObject = context
        saveItem.image = NSImage(systemSymbolName: "photo.badge.arrow.down", accessibilityDescription: nil)

        var items = [saveItem]

        // "Save to Album..." item with submenu — only if album access is authorized.
        if isAlbumAccessAvailable {
            let albums = fetchUserAlbumsSynchronously()
            if !albums.isEmpty {
                let albumItem = NSMenuItem(
                    title: albumTitle,
                    action: nil,
                    keyEquivalent: "",
                )
                albumItem.image = NSImage(
                    systemSymbolName: "rectangle.stack.badge.arrow.down",
                    accessibilityDescription: nil,
                )

                let submenu = NSMenu()
                for album in albums {
                    let item = NSMenuItem(
                        title: album.title,
                        action: #selector((any SaveToPhotosTarget).saveToPhotos(_:)),
                        keyEquivalent: "",
                    )
                    item.target = target
                    item.representedObject = SaveContext(
                        url: context.url,
                        mediaType: context.mediaType,
                        albumID: album.id,
                    )
                    submenu.addItem(item)
                }

                albumItem.submenu = submenu
                items.append(albumItem)
            }
        }

        return items
    }

    /// Fetches user albums synchronously. Only call when `isAlbumAccessAvailable` is true.
    private func fetchUserAlbumsSynchronously() -> [Album] {
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil,
        )

        var albums: [Album] = []
        userAlbums.enumerateObjects { collection, _, _ in
            if let title = collection.localizedTitle {
                albums.append(Album(id: collection.localIdentifier, title: title))
            }
        }

        return albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

// MARK: - Target Protocol

/// Protocol for objects that can handle Save to Photos actions.
@objc
protocol SaveToPhotosTarget {
    @objc
    func saveToPhotos(_ sender: NSMenuItem)
}
