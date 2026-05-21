import AppKit
import WebKit

/// Builds context menus for web pages with enhanced functionality.
///
/// This builder extends WebKit's default context menu by prepending custom items
/// while preserving WebKit's proposed menu items (Open Link, Copy, Look Up, etc.).
///
/// Custom items added:
/// - Data detection: Phone numbers, emails, addresses, dates, flights, tracking numbers
/// - Link actions: Open in New Tab, Open in New Window, Copy Link
/// - Image actions: Save to Photos, Copy Image Address
/// - Video actions: Save to Photos, Copy Video Address
///
/// ## Architecture
///
/// The builder follows a composition pattern similar to `SidebarContextMenus`:
/// - Separate helper methods for each element type (data, links, images, videos)
/// - Items are grouped by element type with separators between groups
/// - A separator divides custom items from WebKit's default items
/// - Future element types can be added as new helper methods
///
/// ## Usage
///
/// ```swift
/// let builder = WebPageContextMenuBuilder()
/// webPage.backingUIDelegate.menuBuilder = builder.buildMenu(proposedMenu:elementInfo:)
/// ```
final class WebPageContextMenuBuilder: NSObject {
    // MARK: - Dependencies

    private let dataDetectionManager: DataDetectionManager
    private let saveToPhotosManager: SaveToPhotosManager

    /// Callback for opening a URL in a new tab.
    var onOpenInNewTab: ((URL) -> Void)?

    /// Callback for the "Remind Me" action. Called when user selects the menu item.
    var onRemindMe: (() -> Void)?

    /// Callback for the "Insert GIF" action. Called when user selects the menu item.
    var onInsertGIF: (() -> Void)?

    /// Callback for speed reading selected text. Receives the selected text.
    var onSpeedReadSelection: ((String) -> Void)?

    /// Callback for downloading a file (image/video) to the Downloads folder.
    var onDownloadFile: ((URL) -> Void)?

    /// Callback for saving media to Photos via the download manager.
    /// Receives the media URL and optional album ID.
    var onSaveToPhotos: ((URL, String?) -> Void)?

    /// Callback for yt-dlp video downloads. Receives the page URL and download mode.
    var onYTDLPDownload: ((URL, YTDLPDownloadMode) -> Void)?

    /// Returns whether yt-dlp downloads are enabled. Set by the caller.
    var isYTDLPEnabled: (() -> Bool)?

    /// Minimum character count for showing "Speed Read Selection" option.
    /// Assumes ~6 chars per word (5 letter avg + space), so 300 chars ≈ 50 words.
    private let speedReadMinCharCount = 300

    // MARK: - Initialization

    init(
        dataDetectionManager: DataDetectionManager = DataDetectionManager(),
        saveToPhotosManager: SaveToPhotosManager = SaveToPhotosManager(),
    ) {
        self.dataDetectionManager = dataDetectionManager
        self.saveToPhotosManager = saveToPhotosManager
    }

    // MARK: - Menu Building

    /// Builds a context menu by prepending custom items to WebKit's proposed menu.
    ///
    /// This is the main entry point for context menu customization. Custom items
    /// are added at the beginning of the menu, followed by a separator, then
    /// WebKit's standard items (Open Link, Copy, Look Up, Search, Share, etc.).
    ///
    /// - Parameters:
    ///   - proposedMenu: WebKit's proposed context menu with standard items.
    ///   - elementInfo: Information about the clicked element.
    /// - Returns: The customized context menu with custom items prepended.
    func buildMenu(proposedMenu: NSMenu, elementInfo: WKContextMenuElementInfoAdapter) -> NSMenu {
        // Collect custom item groups, each group separated from others
        var itemGroups: [[NSMenuItem]] = []

        // Data detection for selected/lookup text (phone, email, address, date, flight, tracking)
        if let selectedText = elementInfo.selectedText, !selectedText.isEmpty {
            let dataItems = dataDetectionManager.createMenuItems(for: selectedText)
            if !dataItems.isEmpty {
                itemGroups.append(dataItems)
            }

            // Speed read for long selections
            let speedReadItems = speedReadSelectionItems(for: selectedText)
            if !speedReadItems.isEmpty {
                itemGroups.append(speedReadItems)
            }
        }

        if let linkURL = elementInfo.linkURL {
            itemGroups.append(linkItems(for: linkURL))
        }

        if let imageURL = elementInfo.imageURL {
            itemGroups.append(imageItems(for: imageURL))
        }

        if let videoURL = elementInfo.videoURL {
            // Only show direct "Save Video to Photos" for non-blob URLs.
            // Blob URLs (HLS/MSE streams) can't be downloaded directly —
            // yt-dlp handles those via the post permalink below.
            if videoURL.scheme != "blob" {
                itemGroups.append(videoItems(for: videoURL))
            }
        }

        // Add emoji picker for editable content
        if elementInfo.isContentEditable {
            itemGroups.append(editableContentItems())
        }

        // Add page-level actions (Remind Me)
        let pageItems = pageActionItems()
        if !pageItems.isEmpty {
            itemGroups.append(pageItems)
        }

        // Add yt-dlp download options for supported video/music sites.
        // When right-clicking a specific video, prefer the post permalink
        // (videoContextURL) over the page URL so yt-dlp targets the right video.
        let ytdlpURL = elementInfo.videoContextURL ?? elementInfo.pageURL
        if let ytdlpURL {
            let ytdlpDownloadItems = ytdlpItems(for: ytdlpURL)
            if !ytdlpDownloadItems.isEmpty {
                itemGroups.append(ytdlpDownloadItems)
            }
        }

        // Return proposed menu unchanged if no custom items
        let nonEmptyGroups = itemGroups.filter { !$0.isEmpty }
        guard !nonEmptyGroups.isEmpty else {
            return proposedMenu
        }

        // Build final menu: custom item groups + separator + WebKit items
        let finalMenu = NSMenu()

        for (index, group) in nonEmptyGroups.enumerated() {
            if index > 0 {
                finalMenu.addItem(.separator())
            }
            for item in group {
                finalMenu.addItem(item)
            }
        }

        // Add separator between custom items and WebKit items.
        // Filter out WebKit's default image/video save/download items since we provide
        // our own (Download Image, Save to Photos). WebKit's defaults trigger Photos
        // library permissions even for plain downloads. Keep items like "Copy Image"
        // that provide distinct functionality.
        let hasImageOrVideo = elementInfo.imageURL != nil || elementInfo.videoURL != nil
        let filteredProposedItems = proposedMenu.items.filter { item in
            if hasImageOrVideo {
                let title = item.title.lowercased()
                let isRedundantItem = title.contains("download") || title.contains("save")
                if isRedundantItem, title.contains("image") || title.contains("picture")
                    || title.contains("video") {
                    return false
                }
            }
            return true
        }

        if !filteredProposedItems.isEmpty {
            finalMenu.addItem(.separator())
            for item in filteredProposedItems {
                finalMenu.addItem(item.copy() as! NSMenuItem)
            }
        }

        return finalMenu
    }

    // MARK: - Menu Item Groups

    /// Returns link-related menu items (open in new tab, copy).
    private func linkItems(for url: URL) -> [NSMenuItem] {
        [
            menuItem("Open Link in New Tab", action: #selector(openInNewTab(_:)), url: url),
            menuItem("Copy Link", action: #selector(copyLink(_:)), url: url),
        ]
    }

    /// Returns image-related menu items (download, save to photos, copy address).
    private func imageItems(for url: URL) -> [NSMenuItem] {
        let downloadItem = menuItem("Download Image", action: #selector(downloadFile(_:)), url: url)
        downloadItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        return [
            downloadItem,
        ] + saveToPhotosManager.createImageMenuItems(for: url, target: self) + [
            menuItem("Copy Image Address", action: #selector(copyLink(_:)), url: url),
        ]
    }

    /// Returns video-related menu items (save to photos, copy address).
    private func videoItems(for url: URL) -> [NSMenuItem] {
        saveToPhotosManager.createVideoMenuItems(for: url, target: self) + [
            menuItem("Copy Video Address", action: #selector(copyLink(_:)), url: url),
        ]
    }

    /// Returns menu items for editable content (input fields, textareas, contenteditable).
    private func editableContentItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        // Emoji picker
        let emojiItem = NSMenuItem(
            title: "Emoji & Symbols",
            action: #selector(showEmojiPicker),
            keyEquivalent: "",
        )
        emojiItem.target = self
        items.append(emojiItem)

        // GIF insertion (only if callback is set)
        if onInsertGIF != nil {
            let gifItem = NSMenuItem(
                title: "Insert GIF...",
                action: #selector(insertGIF),
                keyEquivalent: "",
            )
            gifItem.target = self
            gifItem.image = NSImage(systemSymbolName: "photo.badge.plus", accessibilityDescription: "Insert GIF")
            items.append(gifItem)
        }

        return items
    }

    /// Returns speed read menu items for sufficiently long selected text.
    private func speedReadSelectionItems(for text: String) -> [NSMenuItem] {
        guard onSpeedReadSelection != nil else { return [] }

        // Quick character count check (O(1) for String.count)
        guard text.count >= speedReadMinCharCount else { return [] }

        let item = NSMenuItem(
            title: "Speed Read Selection",
            action: #selector(speedReadSelection(_:)),
            keyEquivalent: "",
        )
        item.target = self
        item.representedObject = text
        item.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: "Speed Read")
        return [item]
    }

    /// Returns page-level action items (Remind Me).
    private func pageActionItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        // Only show Remind Me if a callback is set
        if onRemindMe != nil {
            let remindItem = NSMenuItem(
                title: "Remind Me About This Page...",
                action: #selector(remindMeAboutPage),
                keyEquivalent: "",
            )
            remindItem.target = self
            remindItem.image = NSImage(systemSymbolName: "bell", accessibilityDescription: "Reminder")
            items.append(remindItem)
        }

        return items
    }

    /// Returns yt-dlp download items for supported video/music sites.
    ///
    /// - Parameter pageURL: The URL of the current page.
    /// - Returns: Array of menu items for download options, or empty if not a supported site.
    private func ytdlpItems(for pageURL: URL) -> [NSMenuItem] {
        guard onYTDLPDownload != nil else { return [] }

        // Check if yt-dlp is enabled in settings
        guard isYTDLPEnabled?() ?? true else { return [] }

        // Check if this site is supported by yt-dlp
        guard let mediaType = YTDLPSites.shared.mediaType(for: pageURL) else { return [] }

        var items: [NSMenuItem] = []

        switch mediaType {
        case .video, .mixed:
            // Full video download options
            items.append(ytdlpMenuItem(
                "Download Video",
                mode: .video,
                pageURL: pageURL,
                iconName: "arrow.down.circle",
            ))
            items.append(ytdlpMenuItem(
                "Download Video Only",
                mode: .videoOnly,
                pageURL: pageURL,
                iconName: "film",
            ))
            items.append(ytdlpMenuItem(
                "Download Audio Only",
                mode: .audioOnly,
                pageURL: pageURL,
                iconName: "music.note",
            ))
            items.append(ytdlpMenuItem(
                "Save to Photos",
                mode: .saveToPhotos,
                pageURL: pageURL,
                iconName: "photo.on.rectangle",
            ))

        case .music:
            // Audio-focused sites get simplified options
            items.append(ytdlpMenuItem(
                "Download",
                mode: .audioOnly,
                pageURL: pageURL,
                iconName: "arrow.down.circle",
            ))
        }

        return items
    }

    /// Creates a yt-dlp download menu item.
    private func ytdlpMenuItem(
        _ title: String,
        mode: YTDLPDownloadMode,
        pageURL: URL,
        iconName: String,
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(ytdlpDownload(_:)),
            keyEquivalent: "",
        )
        item.target = self
        item.representedObject = YTDLPDownloadContext(pageURL: pageURL, mode: mode)
        item.image = NSImage(systemSymbolName: iconName, accessibilityDescription: title)
        return item
    }

    private func menuItem(_ title: String, action: Selector, url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = url
        return item
    }

    // MARK: - Actions

    @objc
    private func openInNewTab(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onOpenInNewTab?(url)
    }

    @objc
    private func copyLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    @objc
    private func downloadFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onDownloadFile?(url)
    }

    /// Shows the system emoji and symbols picker.
    ///
    /// The character palette will insert the selected character into the
    /// currently focused text field automatically.
    @objc
    private func showEmojiPicker() {
        NSApp.orderFrontCharacterPalette(nil)
    }

    /// Triggers the "Remind Me" action for the current page.
    @objc
    private func remindMeAboutPage() {
        onRemindMe?()
    }

    /// Triggers the "Insert GIF" action.
    @objc
    private func insertGIF() {
        onInsertGIF?()
    }

    /// Triggers speed reading of selected text.
    @objc
    private func speedReadSelection(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        onSpeedReadSelection?(text)
    }

    @objc
    func saveToPhotos(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? SaveToPhotosManager.SaveContext else { return }
        onSaveToPhotos?(context.url, context.albumID)
    }

    /// Triggers yt-dlp download for the current page.
    @objc
    private func ytdlpDownload(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? YTDLPDownloadContext else { return }
        onYTDLPDownload?(context.pageURL, context.mode)
    }
}

// MARK: - YTDLPDownloadContext

/// Context for yt-dlp download menu items.
private struct YTDLPDownloadContext {
    let pageURL: URL
    let mode: YTDLPDownloadMode
}

// MARK: - SaveToPhotosTarget Conformance

extension WebPageContextMenuBuilder: SaveToPhotosTarget {}
