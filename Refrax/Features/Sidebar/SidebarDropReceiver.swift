import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Invisible NSView that receives drag operations entering the sidebar.
///
/// This view handles three scenarios:
/// 1. **Re-entry**: When a drag that originated in the sidebar (and handed off to AppKit)
///    returns to the sidebar, this view restores the internal drag state.
/// 2. **External URL drops**: When an external app drags URLs into the sidebar,
///    this view coordinates with the DragCoordinator to create tabs/favorites.
/// 3. **External shelf drops**: When non-URL content (text, images, files) is dragged
///    into the sidebar, this view adds items to the global shelf.
///
/// ## Re-Entry Flow
///
/// 1. User drags outside sidebar → AppKit session active, phase = `.external`
/// 2. User drags back in → `draggingEntered` detects Refrax pasteboard type
/// 3. Ghost state restored, phase = `.internal`, SwiftUI overlay reappears
/// 4. `draggingUpdated` tracks cursor position, updating overlay
/// 5. User releases → `performDragOperation` commits via internal drop logic
///
/// ## External Drop Flow
///
/// 1. External app drags URL over sidebar → `draggingEntered` detects URL types
/// 2. `draggingUpdated` determines drop zone based on cursor position
/// 3. `inboundDropZone` updated on coordinator for visual feedback
/// 4. User releases → `performDragOperation` creates tab/favorite based on zone
///
/// ## Shelf Drop Flow
///
/// 1. External app drags non-URL content → `draggingEntered` detects shelf types
/// 2. User releases → `performDragOperation` calls `shelfManager.addItem()`
/// 3. Item stored in Application Support/Shelf/
///
/// ## Thread Safety
///
/// All interactions happen on the main thread (required by both SwiftUI and AppKit).
struct SidebarDropReceiver: NSViewRepresentable {
    /// The drag coordinator that manages drag state.
    var coordinator: Sidebar.DragCoordinator

    /// The shelf manager for handling non-URL drops.
    var shelfManager: ShelfManager

    func makeNSView(context _: Context) -> DropReceiverNSView {
        let view = DropReceiverNSView()
        view.dragCoordinator = coordinator
        view.shelfManager = shelfManager
        return view
    }

    func updateNSView(_ nsView: DropReceiverNSView, context _: Context) {
        nsView.dragCoordinator = coordinator
        nsView.shelfManager = shelfManager
    }
}

/// The actual NSView that implements NSDraggingDestination.
///
/// This class receives AppKit drag events and translates them into
/// DragCoordinator state updates for seamless re-entry handling.
final class DropReceiverNSView: NSView {
    /// Reference to the drag coordinator (set by the representable).
    unowned var dragCoordinator: Sidebar.DragCoordinator!

    /// Reference to the shelf manager (set by the representable).
    unowned var shelfManager: ShelfManager!

    /// Current drag mode being handled.
    private enum DragMode {
        case none
        case reentry
        case externalURL
        case externalShelf
    }

    private var dragMode: DragMode = .none

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Hit Testing

    /// Returns nil to pass through all mouse events to SwiftUI views beneath.
    ///
    /// NSDraggingDestination methods are called based on registered drag types,
    /// not hit testing, so returning nil doesn't affect drag reception.
    /// This is critical: without this override, the full-frame NSView would
    /// intercept all mouse events and prevent SwiftUI drag gestures from working.
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    private func registerForDraggedTypes() {
        // Register for Refrax internal types (for re-entry detection),
        // external URL types (for inbound drops), and shelf types (non-URL content)
        registerForDraggedTypes([
            // Internal types for re-entry
            DragPasteboardType.refraxTabID,
            DragPasteboardType.refraxFavoriteID,
            // External URL types (in priority order)
            .URL,
            .fileURL,
            NSPasteboard.PasteboardType(UTType.fileURL.identifier),
            // Legacy file type for .webloc files
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            // Shelf types (non-URL content)
            .string,
            NSPasteboard.PasteboardType(UTType.image.identifier),
            NSPasteboard.PasteboardType(UTType.tiff.identifier),
            NSPasteboard.PasteboardType(UTType.png.identifier),
        ])
    }
}

// MARK: - NSDraggingDestination

extension DropReceiverNSView {
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard

        // Priority 1: Re-entry from our own AppKit drag session
        if DragPasteboardWriter.containsRefraxDragData(pasteboard) {
            return handleReentryEntered(sender)
        }

        // Priority 2: Web URL → tab creation (existing)
        // Check if there's a URL we can extract (web URL, not just file)
        if containsURLData(pasteboard), extractURL(from: pasteboard) != nil {
            return handleExternalURLEntered(sender)
        }

        // Priority 3: Non-URL content → shelf (NEW)
        if containsShelfableData(pasteboard) {
            return handleExternalShelfEntered(sender)
        }

        // Unknown drag type - reject
        dragMode = .none
        return []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        switch dragMode {
        case .none:
            []
        case .reentry:
            handleReentryUpdated(sender)
        case .externalURL:
            handleExternalURLUpdated(sender)
        case .externalShelf:
            handleExternalShelfUpdated(sender)
        }
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        switch dragMode {
        case .none:
            break
        case .reentry:
            handleReentryExited(sender)
        case .externalURL:
            handleExternalURLExited()
        case .externalShelf:
            handleExternalShelfExited()
        }
    }

    override func prepareForDragOperation(_: any NSDraggingInfo) -> Bool {
        // Accept the drop if we're handling any recognized drag type
        dragMode != .none
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        switch dragMode {
        case .none:
            false
        case .reentry:
            performReentryDrop()
        case .externalURL:
            performExternalURLDrop(sender)
        case .externalShelf:
            performExternalShelfDrop(sender)
        }
    }

    override func concludeDragOperation(_: (any NSDraggingInfo)?) {
        // Cleanup after drag completes
        MainActor.assumeIsolated {
            switch dragMode {
            case .none:
                break
            case .reentry:
                dragCoordinator.reset()
            case .externalURL:
                dragCoordinator.inboundDropZone = nil
            case .externalShelf:
                // No cleanup needed for shelf drops
                break
            }
        }
        dragMode = .none
    }

    override func draggingEnded(_: any NSDraggingInfo) {
        // Final cleanup - drag session has completely ended
        MainActor.assumeIsolated {
            dragCoordinator.inboundDropZone = nil
        }
        dragMode = .none
    }
}

// MARK: - Re-Entry Handling

extension DropReceiverNSView {
    private func handleReentryEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        // Verify we have ghost state (drag originated from this sidebar)
        guard let ghostState = dragCoordinator.ghostState else {
            // No ghost state means this isn't a re-entry we can handle
            dragMode = .none
            return []
        }

        // Debounce: require at least one frame in external phase before re-entry
        // This prevents flickering at the sidebar edge.
        // Return [] (not .move) during debounce to maintain consistent state:
        // dragMode stays .none, so draggingUpdated will also return [].
        guard let externalPhaseStart = dragCoordinator.externalPhaseStartTime,
              CACurrentMediaTime() - externalPhaseStart > 0.016 else {
            // Too soon after exit - reject until debounce period passes
            dragMode = .none
            return []
        }

        // This is a valid re-entry - restore internal drag state
        dragMode = .reentry

        MainActor.assumeIsolated {
            // Hide AppKit drag image so SwiftUI overlay takes visual priority
            dragCoordinator.dragSourceView?.hideDragImage()

            // Convert AppKit window coordinates to SwiftUI global coordinates
            let globalLocation = convertToGlobalCoordinates(sender.draggingLocation)

            // Calculate offset delta from handoff position to current position.
            // Ghost state preserves the offset at handoff time; we add the movement since then.
            // This avoids coordinate system conversion issues by working with deltas only.
            let handoffPosition = ghostState.overlayPosition
            let deltaY = globalLocation.y - handoffPosition.y

            // Restore coordinator state from ghost (includes currentOffset and originalFrame)
            dragCoordinator.restoreFromGhostState(ghostState)

            // Apply the delta to get the new offset
            dragCoordinator.currentOffset = ghostState.currentOffset + deltaY

            // Update overlay position to current location
            dragCoordinator.overlayPosition = globalLocation

            // Transition back to internal phase (shows SwiftUI overlay)
            dragCoordinator.handoffPhase = .internal
        }

        return .move
    }

    /// Convert AppKit window coordinates to SwiftUI global coordinates.
    ///
    /// AppKit's `draggingLocation` uses bottom-left origin (Y increases upward).
    /// SwiftUI's `.global` coordinate space uses top-left origin (Y increases downward).
    /// Both are relative to the window's content area.
    private func convertToGlobalCoordinates(_ windowPoint: NSPoint) -> CGPoint {
        guard let window, let contentView = window.contentView else {
            // Fallback: return as-is (may be wrong but better than nothing)
            return CGPoint(x: windowPoint.x, y: windowPoint.y)
        }

        // Flip Y using content view height to convert from bottom-left to top-left origin
        let contentHeight = contentView.bounds.height
        return CGPoint(x: windowPoint.x, y: contentHeight - windowPoint.y)
    }

    private func handleReentryUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        // Convert AppKit window coordinates to SwiftUI global coordinates
        let globalLocation = convertToGlobalCoordinates(sender.draggingLocation)

        MainActor.assumeIsolated {
            // Track movement delta from previous position
            let previousPosition = dragCoordinator.overlayPosition
            let deltaY = globalLocation.y - previousPosition.y

            // Update offset by adding the delta (preserves correct offset from entry)
            dragCoordinator.currentOffset += deltaY

            // Update overlay position
            dragCoordinator.overlayPosition = globalLocation

            // Update drop zone detection and affected items
            // Note: detectDropTarget expects global coordinates (same as gesture location
            // during normal drag), not sidebar-local coordinates
            dragCoordinator.detectDropTarget(at: dragCoordinator.overlayPosition)
            dragCoordinator.updateAffectedItems()
        }

        return .move
    }

    private func handleReentryExited(_: (any NSDraggingInfo)?) {
        // Drag left the sidebar again - go back to external phase
        MainActor.assumeIsolated {
            // Capture new ghost state at current position
            dragCoordinator.ghostState = dragCoordinator.captureGhostState()

            // Restore the AppKit drag image (it was hidden on re-entry)
            dragCoordinator.dragSourceView?.restoreDragImage()

            // Transition back to external phase
            dragCoordinator.handoffPhase = .external
            dragCoordinator.externalPhaseStartTime = CACurrentMediaTime()

            // Clear visual state
            dragCoordinator.itemPushOffsets.removeAll()
        }

        dragMode = .none
    }

    private func performReentryDrop() -> Bool {
        // Commit the internal drag operation
        let success = MainActor.assumeIsolated {
            dragCoordinator.commitDrag()
        }
        return success
    }
}

// MARK: - External URL Handling

extension DropReceiverNSView {
    private func handleExternalURLEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        // Validate early: only accept if we can actually extract a URL.
        // This prevents showing drop zone feedback for files we can't use
        // (e.g., images, PDFs, or other non-web files).
        guard extractURL(from: sender.draggingPasteboard) != nil else {
            dragMode = .none
            return []
        }

        dragMode = .externalURL

        // Determine initial drop zone using SwiftUI-compatible coordinates
        let globalLocation = convertToGlobalCoordinates(sender.draggingLocation)
        MainActor.assumeIsolated {
            dragCoordinator.inboundDropZone = determineDropZone(at: globalLocation)
        }

        return .copy
    }

    private func handleExternalURLUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let globalLocation = convertToGlobalCoordinates(sender.draggingLocation)

        MainActor.assumeIsolated {
            dragCoordinator.inboundDropZone = determineDropZone(at: globalLocation)
        }

        return .copy
    }

    private func handleExternalURLExited() {
        MainActor.assumeIsolated {
            dragCoordinator.inboundDropZone = nil
        }
        dragMode = .none
    }

    private func performExternalURLDrop(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        // Extract URL from pasteboard
        guard let url = extractURL(from: pasteboard) else {
            return false
        }

        // Use SwiftUI-compatible coordinates for drop zone detection
        let globalLocation = convertToGlobalCoordinates(sender.draggingLocation)
        let dropZone = MainActor.assumeIsolated {
            determineDropZone(at: globalLocation)
        }

        // Check if this URL looks like a downloadable file (image, PDF, etc.)
        // If so, try to download it to the shelf instead of opening as a tab
        if shouldTryShelfDownload(url: url, dropZone: dropZone) {
            Task { @MainActor in
                let result = await shelfManager.addItemFromURL(url)
                switch result {
                case .addedToShelf:
                    // Successfully added to shelf, nothing more to do
                    break
                case .openAsTab, .failed:
                    // Couldn't download or content is HTML - open as tab
                    _ = createTabFromURL(url, isPinned: false)
                }
            }
            return true
        }

        // Create tab or favorite based on drop zone
        return MainActor.assumeIsolated {
            switch dropZone {
            case .favoritesGrid:
                // Create shortcut favorite
                createFavoriteFromURL(url)

            case .pinnedSection:
                // Create pinned tab
                createTabFromURL(url, isPinned: true)

            case .normalSection:
                // Create normal tab
                createTabFromURL(url, isPinned: false)

            case .groupHeader:
                // For now, create as normal tab (could add to group in future)
                createTabFromURL(url, isPinned: false)

            case .none:
                // No valid drop zone - create as normal tab
                createTabFromURL(url, isPinned: false)
            }
        }
    }

    /// Determines if a URL should be downloaded to shelf vs opened as a tab.
    ///
    /// Returns true for URLs that look like downloadable files (images, PDFs, etc.)
    /// when dropped anywhere except the favorites grid.
    private func shouldTryShelfDownload(url: URL, dropZone: Sidebar.DragCoordinator.DropZone?) -> Bool {
        // Don't intercept favorites grid drops - those should create shortcuts
        if dropZone == .favoritesGrid {
            return false
        }

        // Only process http/https URLs
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        // Check if the URL path has a file-like extension
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return false }

        // Extensions that should go to shelf (images, documents, media)
        let downloadExtensions: Set<String> = [
            // Images
            "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "svg", "ico", "bmp", "tiff",
            // Documents
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            // Archives
            "zip", "rar", "7z", "tar", "gz",
            // Media
            "mp3", "mp4", "mov", "avi", "mkv", "wav", "flac",
            // Other common downloads
            "dmg", "pkg", "exe", "msi",
        ]

        return downloadExtensions.contains(ext)
    }

    /// Determine which drop zone the cursor is over.
    private func determineDropZone(at location: CGPoint) -> Sidebar.DragCoordinator.DropZone? {
        let favoritesFrame = dragCoordinator.favoritesGridFrame
        let pinnedFrame = dragCoordinator.computedPinnedSectionFrame
        let normalFrame = dragCoordinator.computedNormalSectionFrame

        if favoritesFrame.contains(location) {
            return .favoritesGrid
        } else if pinnedFrame.contains(location) {
            return .pinnedSection
        } else if normalFrame.contains(location) {
            return .normalSection
        }

        // Default to normal section if cursor is in sidebar but not in a specific zone
        return .normalSection
    }

    /// Create a tab from a dropped URL.
    private func createTabFromURL(_ url: URL, isPinned: Bool) -> Bool {
        guard let tabManager = dragCoordinator.tabManager else { return false }

        let tab = tabManager.createTab(url: url, isPinned: isPinned, makeActive: true)
        return tab.id != UUID() // Check that a valid tab was created
    }

    /// Create a shortcut favorite from a dropped URL.
    private func createFavoriteFromURL(_ url: URL) -> Bool {
        guard let tabManager = dragCoordinator.tabManager,
              let bookmarksManager = tabManager.bookmarksManager else { return false }

        let title = url.host ?? url.absoluteString
        _ = bookmarksManager.createBookmark(
            url: url,
            title: title,
            isFavorite: true,
            favoriteMode: .shortcut,
        )
        return true
    }
}

// MARK: - External Shelf Handling

extension DropReceiverNSView {
    /// Check if pasteboard contains non-URL content suitable for the shelf.
    private func containsShelfableData(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []

        // Check for text
        if types.contains(.string) {
            return true
        }

        // Check for images
        let imageTypes: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType(UTType.image.identifier),
            NSPasteboard.PasteboardType(UTType.tiff.identifier),
            NSPasteboard.PasteboardType(UTType.png.identifier),
            .png,
            .tiff,
        ]
        if imageTypes.contains(where: types.contains) {
            return true
        }

        // Check for file URLs that aren't web URLs or .webloc files
        if types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType(UTType.fileURL.identifier)) {
            // Only accept as shelf content if it's NOT a web-openable file
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                for url in urls where url.isFileURL {
                    let ext = url.pathExtension.lowercased()
                    // Exclude .webloc files (they should create tabs)
                    if ext != "webloc" {
                        return true
                    }
                }
            }
        }

        return false
    }

    /// Handle external shelf drag entered.
    private func handleExternalShelfEntered(_: any NSDraggingInfo) -> NSDragOperation {
        dragMode = .externalShelf
        return .copy
    }

    /// Handle external shelf drag updated.
    private func handleExternalShelfUpdated(_: any NSDraggingInfo) -> NSDragOperation {
        // No visual feedback needed for shelf drops (items go to global shelf)
        .copy
    }

    /// Handle external shelf drag exited.
    private func handleExternalShelfExited() {
        dragMode = .none
    }

    /// Perform the external shelf drop.
    private func performExternalShelfDrop(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        // Add items to shelf asynchronously
        Task { @MainActor in
            await shelfManager.addItem(from: pasteboard)
        }

        return true
    }
}

// MARK: - URL Extraction

extension DropReceiverNSView {
    /// Check if pasteboard contains URL data we can extract.
    private func containsURLData(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        return types.contains(.URL)
            || types.contains(.fileURL)
            || types.contains(NSPasteboard.PasteboardType(UTType.fileURL.identifier))
            || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
    }

    /// Extract URL from pasteboard, handling various formats including .webloc files.
    private func extractURL(from pasteboard: NSPasteboard) -> URL? {
        // Try direct URL first
        if let urlString = pasteboard.string(forType: .URL),
           let url = URL(string: urlString) {
            return url
        }

        // Try file URLs (might be .webloc files)
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for fileURL in fileURLs {
                // Check if it's a .webloc file
                if fileURL.pathExtension.lowercased() == "webloc" {
                    if let extractedURL = extractURLFromWebloc(fileURL) {
                        return extractedURL
                    }
                }

                // If it's a web URL (not a file path), use it directly
                if fileURL.scheme == "http" || fileURL.scheme == "https" {
                    return fileURL
                }
            }
        }

        // Try legacy filename type
        if let filenames = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            for filename in filenames {
                let fileURL = URL(fileURLWithPath: filename)
                if fileURL.pathExtension.lowercased() == "webloc" {
                    if let extractedURL = extractURLFromWebloc(fileURL) {
                        return extractedURL
                    }
                }
            }
        }

        return nil
    }

    /// Extract URL from a .webloc file (plist format).
    private func extractURLFromWebloc(_ fileURL: URL) -> URL? {
        guard let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let urlString = plist["URL"] as? String,
              let url = URL(string: urlString) else {
            return nil
        }
        return url
    }
}
