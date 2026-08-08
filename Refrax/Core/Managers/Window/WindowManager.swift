import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Central manager for window lifecycle and operations.
///
/// `WindowManager` coordinates all browser windows and provides access to window
/// controllers. It works closely with `TabManager` for tab-related operations
/// that affect windows.
///
/// ## Initialization Order
///
/// Due to circular dependency between WindowManager and TabManager, initialization
/// uses late-bound references:
/// ```swift
/// let windowManager = WindowManager(modelContainer: ...)
/// let tabManager = TabManager(state: ..., pagePool: ..., ...)
/// windowManager.tabManager = tabManager
/// tabManager.windowManager = windowManager
/// ```
///
/// ## Window Access Patterns
///
/// ```swift
/// // Active window (key or main)
/// windowManager.activeWindowController?.windowState
///
/// // All windows showing a specific space
/// for controller in windowManager.windowControllers {
///     if controller.windowState.activeSpaceID == space.id { ... }
/// }
///
/// // Create new window
/// let controller = windowManager.createWindow()
/// ```
@Observable
final class WindowManager {
    // MARK: - Properties

    private(set) var windowControllers: [RefraxWindowController] = []
    @ObservationIgnored private var windowObservers: [ObjectIdentifier: any NSObjectProtocol] = [:]
    private var didBecomeKeyObserver: (any NSObjectProtocol)?

    /// Active reference pane window controllers, keyed by parent WindowState.
    ///
    /// Each browser window can have at most one reference pane window open.
    /// When the parent window closes or the reference pane window is closed,
    /// the entry is removed.
    @ObservationIgnored private var referencePaneWindowControllers: [ObjectIdentifier: ReferencePaneWindowController] = [:]

    /// Observers for reference pane window close notifications, keyed by parent WindowState.
    @ObservationIgnored private var referencePaneCloseObservers: [ObjectIdentifier: any NSObjectProtocol] = [:]

    /// Active Glimpse window controllers.
    ///
    /// Glimpse windows are lightweight ephemeral windows for quick browsing tasks.
    /// They are not persisted across app restarts.
    private(set) var glimpseWindowControllers: [GlimpseController] = []

    /// The most recently active browser window controller.
    ///
    /// This is updated whenever a browser window becomes key. Unlike `activeWindowController`,
    /// this persists even when non-browser windows (like Web Inspector or Settings) become key.
    /// Use this for menu actions that should target the last active browser window.
    private(set) weak var lastActiveBrowserWindowController: RefraxWindowController?

    let modelContainer: ModelContainer

    /// Tab manager for tab operations.
    ///
    /// Set after initialization to break circular dependency during setup.
    /// Both managers are app-lifetime singletons, so the cycle is intentional.
    unowned var tabManager: TabManager!

    /// Bookmarks manager for bookmark operations.
    ///
    /// Set after initialization, used for import/export features.
    unowned var bookmarksManager: BookmarksManager!

    /// History manager for history export.
    ///
    /// Set after initialization, used for history export functionality.
    unowned var historyManager: HistoryManager!

    // MARK: - Computed Properties

    /// Gets the frontmost (key) window controller.
    var frontmostWindowController: RefraxWindowController? {
        guard let keyWindow = NSApplication.shared.keyWindow else { return nil }
        return windowControllers.first { $0.window === keyWindow }
    }

    /// Gets the main window controller (fallback if no key window).
    var mainWindowController: RefraxWindowController? {
        guard let mainWindow = NSApplication.shared.mainWindow else { return nil }
        return windowControllers.first { $0.window === mainWindow }
    }

    /// Gets the active window controller (key, main, or last active browser).
    ///
    /// Use this for operations that should target the user's current focus.
    /// Falls back to the last active browser window when non-browser windows
    /// (like Bookmarks, History, or Settings) are frontmost.
    var activeWindowController: RefraxWindowController? {
        frontmostWindowController ?? mainWindowController ?? lastActiveBrowserWindowController
    }

    /// Whether any windows are open.
    var hasWindows: Bool {
        !windowControllers.isEmpty
    }
    
    /// All window states for iteration.
    ///
    /// Use when you need to update state across all windows.
    var allWindowStates: [WindowState] {
        windowControllers.map(\.windowState)
    }

    // MARK: - Initialization

    /// Creates a WindowManager.
    ///
    /// - Parameter modelContainer: SwiftData container for persistence.
    ///
    /// - Important: Set `tabManager` after initialization to complete the dependency wiring.
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer

        // Observe when any window becomes key to track the last active browser window
        self.didBecomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main,
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }

            MainActor.assumeIsolated {
                // Check if this is one of our browser windows
                if let controller = self?.windowControllers.first(where: { $0.window === window }) {
                    self?.lastActiveBrowserWindowController = controller

                    // Notify extensions of window focus
                    if let extensionManager = self?.tabManager?.state.extensionManager {
                        let extensionWindow = extensionManager.extensionWindow(
                            for: controller.windowState,
                            nsWindow: window,
                        )
                        if let space = controller.windowState.activeSpace {
                            extensionManager.controller(for: space).didFocusWindow(extensionWindow)
                        } else {
                            extensionManager.defaultController.didFocusWindow(extensionWindow)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Window Management

    /// Creates a new browser window.
    ///
    /// The window is registered, initialized with tab state, sized, and displayed.
    /// New windows don't start with an active tab selected.
    ///
    /// - Returns: The created window controller.
    @discardableResult
    func createWindow() -> RefraxWindowController {
        let window = RefraxWindow()
        let windowController = RefraxWindowController(window: window)

        registerWindowController(windowController)
        tabManager.initializeWindow(windowController.windowState)

        sizeAndShow(windowController)

        return windowController
    }

    /// Creates a new window showing a specific space.
    ///
    /// New windows don't start with an active tab selected.
    ///
    /// - Parameter space: The space to display in the new window.
    /// - Returns: The created window controller.
    @discardableResult
    func createWindow(with space: Space) -> RefraxWindowController {
        let window = RefraxWindow()
        let windowController = RefraxWindowController(window: window)

        registerWindowController(windowController)
        tabManager.initializeWindow(windowController.windowState, with: space)

        sizeAndShow(windowController)

        return windowController
    }

    /// Creates a new window without initializing tab state.
    ///
    /// Used during first launch to show the window immediately before DB restoration.
    /// The caller is responsible for calling `initializeWindow` on the window state.
    ///
    /// - Returns: The created window controller (not yet initialized with tab data).
    @discardableResult
    func createWindowWithoutInitialization() -> RefraxWindowController {
        let window = RefraxWindow()
        let windowController = RefraxWindowController(window: window)

        registerWindowController(windowController)

        sizeAndShow(windowController)

        return windowController
    }

    /// Sizes and shows a newly created window.
    ///
    /// A new window inherits the frontmost browser window's geometry, offset
    /// slightly so the two don't stack exactly. With no window open it reuses
    /// the persisted geometry of the last closed window, so closing the last
    /// window and reopening one keeps the user's size, position, and sidebar
    /// width. With neither available, it falls back to the default size,
    /// centered.
    private func sizeAndShow(_ windowController: RefraxWindowController) {
        guard let window = windowController.window else {
            windowController.showWindow(nil)
            return
        }

        if let geometry = liveGeometry(excluding: windowController)
            ?? WindowGeometryStore.restore(for: NSScreen.main) {
            windowController.applyInitialGeometry(geometry)
            windowController.showWindow(nil)
        } else {
            window.setContentSize(.defaultWindowSize)
            windowController.showWindow(nil)
            window.center()
        }
    }

    /// Snapshots the frontmost browser window's geometry as the template for
    /// a new window, cascaded down-right so the windows don't overlap exactly.
    ///
    /// Returns `nil` when no other browser window exists or the frontmost one
    /// is fullscreen.
    private func liveGeometry(excluding windowController: RefraxWindowController) -> SavedWindowGeometry? {
        let source: RefraxWindowController? = if let active = activeWindowController, active !== windowController {
            active
        } else {
            windowControllers.first { $0 !== windowController && $0.window != nil }
        }

        guard let source,
              let sourceWindow = source.window,
              !sourceWindow.styleMask.contains(.fullScreen)
        else { return nil }

        var frame = sourceWindow.frame
        let cascadeOffset: CGFloat = 24
        let cascaded = frame.offsetBy(dx: cascadeOffset, dy: -cascadeOffset)
        if let visibleFrame = sourceWindow.screen?.visibleFrame,
           visibleFrame.contains(cascaded) {
            frame = cascaded
        }

        return SavedWindowGeometry(
            frame: frame,
            sidebarWidth: source.windowState.sidebarThickness,
            isSidebarCollapsed: source.windowState.isSidebarCollapsed,
            inspectorWidth: source.windowState.referencePaneDockedWidth,
        )
    }

    /// Registers a window controller for lifecycle management.
    ///
    /// Call this for both new and restored windows. Sets up close notification
    /// observation for cleanup.
    func registerWindowController(_ windowController: RefraxWindowController) {
        guard let window = windowController.window else { return }

        let controllerID = ObjectIdentifier(windowController)
        windowControllers.append(windowController)

        // Notify extensions of new window
        if let extensionManager = tabManager?.state.extensionManager {
            let extensionWindow = extensionManager.extensionWindow(
                for: windowController.windowState,
                nsWindow: window,
            )
            if let space = windowController.windowState.activeSpace {
                extensionManager.controller(for: space).didOpenWindow(extensionWindow)
            } else {
                extensionManager.defaultController.didOpenWindow(extensionWindow)
            }
        }

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main,
        ) { [weak self] notification in
            guard let closedWindow = notification.object as? NSWindow else { return }

            MainActor.assumeIsolated {
                self?.handleWindowClosed(closedWindow)
            }
        }

        windowObservers[controllerID] = observer
    }

    /// Handles window close event.
    ///
    /// Saves state, closes any detached reference pane, clears navigation,
    /// removes observer, and handles app quit if this was the last window.
    private func handleWindowClosed(_ closedWindow: NSWindow) {
        guard let index = windowControllers.firstIndex(where: { $0.window === closedWindow }) else {
            return
        }

        let controller = windowControllers.remove(at: index)

        if !closedWindow.styleMask.contains(.fullScreen) {
            WindowGeometryStore.save(
                SavedWindowGeometry(
                    frame: closedWindow.frame,
                    sidebarWidth: controller.windowState.sidebarThickness,
                    isSidebarCollapsed: controller.windowState.isSidebarCollapsed,
                    inspectorWidth: controller.windowState.referencePaneDockedWidth,
                ),
                screen: closedWindow.screen,
            )
        }

        // Notify extensions of window close (before cleanup)
        if let extensionManager = tabManager?.state.extensionManager {
            let extensionWindow = extensionManager.extensionWindow(
                for: controller.windowState,
                nsWindow: closedWindow,
            )
            if let space = controller.windowState.activeSpace {
                extensionManager.controller(for: space).didCloseWindow(extensionWindow)
            } else {
                extensionManager.defaultController.didCloseWindow(extensionWindow)
            }
            extensionManager.removeWindowAdapter(for: controller.windowState)
        }

        if let space = controller.windowState.activeSpace {
            tabManager.saveSpaceState(space)
        }

        // Close any detached reference pane window associated with this parent
        let parentID = ObjectIdentifier(controller.windowState)
        if let referencePaneController = referencePaneWindowControllers[parentID] {
            referencePaneController.window?.close()
            // Note: The close notification handler will clean up tracking state
        }

        controller.windowState.clearNavigationState()

        let controllerID = ObjectIdentifier(controller)
        if let observer = windowObservers.removeValue(forKey: controllerID) {
            NotificationCenter.default.removeObserver(observer)
        }

        // Save state when last window closes
        if windowControllers.isEmpty {
            Task {
                await tabManager.saveImmediately()
            }
        }
    }
    
    /// Finds windows showing a specific space.
    ///
    /// - Parameter space: The space to find windows for.
    /// - Returns: Array of window controllers showing the space.
    func windowControllers(for space: Space) -> [RefraxWindowController] {
        windowControllers.filter { $0.windowState.activeSpaceID == space.id }
    }

    /// Finds the first window controller showing a specific space.
    ///
    /// - Parameter space: The space to find a window for.
    /// - Returns: The first window controller showing the space, or `nil`.
    func windowController(for space: Space) -> RefraxWindowController? {
        windowControllers.first { $0.windowState.activeSpaceID == space.id }
    }

    // MARK: - URL Handling

    /// Opens a URL in the most appropriate browser window.
    ///
    /// Prefers the frontmost browser window if available. Falls back to the last active
    /// browser window (useful when a non-browser window like Settings is key), then
    /// to creating a new window.
    func openURL(_ url: URL) {
        // Prefer frontmost browser window, then last active, then create new
        let controller = frontmostWindowController ?? lastActiveBrowserWindowController ?? createWindow()
        guard let space = controller.windowState.activeSpace ?? tabManager.state.spaces.first else { return }
        tabManager.createTab(url: url, in: space, makeActive: true, loadImmediately: true)
    }

    /// Opens a URL from an external application.
    ///
    /// Uses the ExternalURLHandler to apply user-configured rules before opening.
    /// This is the entry point for URLs opened via system events, `open` command,
    /// or other external sources.
    ///
    /// - Parameters:
    ///   - url: The URL to open.
    ///   - sourceAppBundleID: The bundle ID of the source application, if known.
    ///     Pass `nil` if the source cannot be determined.
    func openExternalURL(_ url: URL, sourceAppBundleID: String? = nil) {
        let settings = BrowserSettings.fetch(in: tabManager.state.modelContext)
        let handler = ExternalURLHandler(
            tabManager: tabManager,
            windowManager: self,
            settings: settings,
        )

        // Try custom handling first
        if handler.openExternal(url, from: sourceAppBundleID) {
            return
        }

        // Fall back to default behavior
        openURL(url)
    }

    // MARK: - Window Actions

    /// Opens the Command Lens in the frontmost window (or creates new window).
    func openCommandLens() {
        guard let controller = activeWindowController else {
            createWindow()
            return
        }

        controller.openCommandLens()
    }

    /// Opens address lens in the frontmost window.
    func openLocation() {
        guard let controller = activeWindowController else { return }
        controller.openAddressLens()
    }
    
    /// Shows the bookmark import wizard.
    func showBookmarkImport() {
        NSApp.typedDelegate.bookmarksWindowController.showWindow()
    }

    /// Exports bookmarks to an HTML file.
    ///
    /// Presents a save panel to the user to choose the destination.
    func exportBookmarksHTML() {
        guard let window = NSApp.keyWindow ?? activeWindowController?.window else { return }

        Task { @MainActor in
            do {
                let exporter = BookmarkExporter(modelContainer: modelContainer)
                let result = try await exporter.exportToHTML()

                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.html]
                savePanel.nameFieldStringValue = result.url.lastPathComponent
                savePanel.canCreateDirectories = true

                let response = await savePanel.beginSheetModal(for: window)

                if response == .OK, let destinationURL = savePanel.url {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.moveItem(at: result.url, to: destinationURL)
                    self.activeWindowController?.windowState.showToast("Exported \(result.count) bookmarks to \(destinationURL.lastPathComponent)")
                } else {
                    try? FileManager.default.removeItem(at: result.url)
                }
            } catch {
                Logger.error("Export failed: \(error)", category: Logger.data)
            }
        }
    }

    /// Exports bookmarks to a JSON file.
    ///
    /// Presents a save panel to the user to choose the destination.
    func exportBookmarksJSON() {
        guard let window = NSApp.keyWindow ?? activeWindowController?.window else { return }

        Task { @MainActor in
            do {
                let exporter = BookmarkExporter(modelContainer: modelContainer)
                let result = try await exporter.exportToJSON()

                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.json]
                savePanel.nameFieldStringValue = result.url.lastPathComponent
                savePanel.canCreateDirectories = true

                let response = await savePanel.beginSheetModal(for: window)

                if response == .OK, let destinationURL = savePanel.url {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.moveItem(at: result.url, to: destinationURL)
                    self.activeWindowController?.windowState.showToast("Exported \(result.count) bookmarks to \(destinationURL.lastPathComponent)")
                } else {
                    try? FileManager.default.removeItem(at: result.url)
                }
            } catch {
                Logger.error("Export failed: \(error)", category: Logger.data)
            }
        }
    }

    /// Shows the history export dialog.
    ///
    /// Presents a dialog with date range pickers and quick presets
    /// for exporting browsing history to Safari-compatible JSON.
    func showHistoryExport() {
        guard let window = NSApp.keyWindow ?? activeWindowController?.window else { return }

        showHistoryExportDialog(in: window)
    }

    /// Shows the history export dialog as a sheet.
    private func showHistoryExportDialog(in parentWindow: NSWindow) {
        let exportView = HistoryExportDialog(
            onExport: { [weak self] fromDate, toDate in
                self?.performHistoryExport(from: fromDate, to: toDate, in: parentWindow)
            },
            onCancel: {
                parentWindow.endSheet(parentWindow.attachedSheet ?? parentWindow)
            },
        )
        .environment(historyManager)

        let hostingController = NSHostingController(rootView: exportView)
        let sheet = NSPanel(contentViewController: hostingController)
        sheet.styleMask = NSWindow.StyleMask([.titled, .closable])
        sheet.title = "Export History"

        parentWindow.beginSheet(sheet)
    }

    /// Performs the history export after user confirms.
    private func performHistoryExport(from startDate: Date, to endDate: Date, in parentWindow: NSWindow) {
        // Close the sheet first
        if let sheet = parentWindow.attachedSheet {
            parentWindow.endSheet(sheet)
        }

        Task { @MainActor in
            do {
                let exporter = HistoryExporter(historyManager: historyManager)
                let tempURL = try await exporter.exportToJSON(from: startDate, to: endDate)

                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.json]
                savePanel.nameFieldStringValue = tempURL.lastPathComponent
                savePanel.canCreateDirectories = true

                let response = await savePanel.beginSheetModal(for: parentWindow)

                if response == .OK, let destinationURL = savePanel.url {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)

                    // Count entries for toast
                    let count = await exporter.entryCount(from: startDate, to: endDate)
                    self.activeWindowController?.windowState.showToast("Exported \(count) history entries")
                } else {
                    try? FileManager.default.removeItem(at: tempURL)
                }
            } catch {
                Logger.error("History export failed: \(error)", category: Logger.data)
                self.activeWindowController?.windowState.showToast("Failed to export history")
            }
        }
    }

    /// Shows the find navigator in the active window.
    func showPageSearch() {
        activeWindowController?.windowState.showFindNavigator()
    }

    /// Import bookmarks from an HTML file with preview.
    ///
    /// Opens a file picker for HTML files, parses the bookmarks,
    /// shows a preview dialog, then commits the import on confirmation.
    func importBookmarksFromFile() {
        guard let window = NSApp.keyWindow ?? activeWindowController?.window else { return }

        Task { @MainActor in
            // Show open panel for HTML files
            let openPanel = NSOpenPanel()
            openPanel.allowedContentTypes = [.html]
            openPanel.allowsMultipleSelection = false
            openPanel.canChooseDirectories = false
            openPanel.message = "Select a bookmarks HTML file to import"

            let response = await openPanel.beginSheetModal(for: window)
            guard response == .OK, let fileURL = openPanel.url else { return }

            do {
                // Parse the HTML file
                let folders = try await bookmarksManager.parseBookmarksFile(from: fileURL)

                if folders.isEmpty {
                    self.activeWindowController?.windowState.showToast("No bookmarks found in file")
                    return
                }

                // Find conflicts
                let conflicts = bookmarksManager.findConflictingFolders(folders)

                // Show preview
                showBookmarkImportPreview(
                    folders: folders,
                    conflicts: conflicts,
                    in: window,
                )
            } catch {
                Logger.error("Failed to parse bookmarks file: \(error)", category: Logger.data)
                self.activeWindowController?.windowState.showToast("Failed to read bookmarks file")
            }
        }
    }

    /// Shows the bookmark import preview dialog.
    private func showBookmarkImportPreview(
        folders: [ImportedFolder],
        conflicts: [String],
        in parentWindow: NSWindow,
    ) {
        let previewView = BookmarkImportPreview(
            folders: folders,
            conflicts: conflicts,
            onImport: { [weak self] in
                self?.commitBookmarkImport(folders: folders, in: parentWindow)
            },
            onCancel: {
                parentWindow.endSheet(parentWindow.attachedSheet ?? parentWindow)
            },
        )

        let hostingController = NSHostingController(rootView: previewView)
        let sheet = NSPanel(contentViewController: hostingController)
        sheet.styleMask = NSWindow.StyleMask([.titled, .closable])
        sheet.title = "Import Bookmarks"

        parentWindow.beginSheet(sheet)
    }

    /// Commits the parsed bookmark import.
    private func commitBookmarkImport(folders: [ImportedFolder], in parentWindow: NSWindow) {
        // Dismiss the sheet first
        if let sheet = parentWindow.attachedSheet {
            parentWindow.endSheet(sheet)
        }

        // Perform import
        let result = bookmarksManager.commitImport(folders)

        // Show result toast
        if result.isFullySuccessful {
            activeWindowController?.windowState.showToast(
                "Imported \(result.bookmarksImported) bookmarks into \(result.foldersCreated) folders",
            )
        } else {
            activeWindowController?.windowState.showToast(
                "Imported \(result.bookmarksImported) bookmarks (\(result.failedBookmarks.count) failed)",
            )
        }
    }

    // MARK: - Reference Pane Window

    /// Creates a separate window for the reference pane.
    ///
    /// The reference pane content is moved from the inspector panel to a new window.
    /// The inspector panel in the source window is collapsed (mode set to `.hidden`).
    ///
    /// ## Behavior
    ///
    /// - If a reference pane window already exists for this window, it is brought to front
    /// - The new window shares the same WindowState as the parent
    /// - When the window closes, mode returns to `.hidden`
    /// - When space changes, the window updates to show new space's reference tabs
    ///
    /// - Parameter parentController: The browser window controller that owns the reference pane.
    @discardableResult
    func createReferencePaneWindow(from parentController: RefraxWindowController) -> ReferencePaneWindowController {
        let parentID = ObjectIdentifier(parentController.windowState)

        // If window already exists, bring it to front
        if let existing = referencePaneWindowControllers[parentID] {
            existing.window?.makeKeyAndOrderFront(nil)
            return existing
        }

        // Calculate initial size matching the docked pane dimensions.
        // Uses the inspector width (clamped to minimum) and the parent window's content height.
        let width = max(parentController.windowState.referencePaneDockedWidth, ReferencePaneWindow.minimumWidth)
        let height: CGFloat = parentController.window?.contentView?.bounds.height ?? 600
        let size = NSSize(width: width, height: height)

        // Mark that a reference pane window is about to exist.
        // This prevents the docked view from forcing WebViews inactive.
        parentController.windowState.hasReferencePaneWindow = true

        // Claim ownership for the reference tab's WebPage BEFORE collapsing the inspector.
        // This ensures the WebViewContainer sees isCurrentOwner=true and doesn't enter portal mode.
        // Without this, the ownership check would fail because:
        // 1. Both docked and separate window share the same WindowState
        // 2. windowState.window points to the MAIN window
        // 3. When ref pane window becomes key, isWindowKey becomes false
        // 4. If ownerID is nil, isOwner would be false
        // Note: Only claim if a reference tab is already selected - we don't auto-select.
        if let space = parentController.windowState.activeSpace,
           let activeRefTabID = parentController.windowState.activeReferenceTabID,
           let activeTab = space.referenceTabs.first(where: { $0.id == activeRefTabID }),
           let webPage = tabManager.pagePool.existingPage(for: activeTab.activePage) {
            webPage.claimOwnership(for: parentController.windowState)
        }

        // Collapse the docked inspector BEFORE creating window controller.
        // This ensures the docked view stops rendering WebViewContainer.
        parentController.windowState.isInspectorCollapsed = true

        // Create new reference pane window.
        let controller = ReferencePaneWindowController(
            parentWindowState: parentController.windowState,
            environment: parentController.environment,
        )

        // Track the window immediately so subsequent calls return the same controller
        referencePaneWindowControllers[parentID] = controller

        // Observe window close to clean up tracking
        if let window = controller.window {
            let observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main,
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.cleanupReferencePaneWindow(parentID: parentID)
                }
            }
            referencePaneCloseObservers[parentID] = observer
        }

        // Show the window after a brief delay to allow SwiftUI to process mode change
        DispatchQueue.main.async {
            controller.showWindow(size: size, relativeTo: parentController.window)
        }

        return controller
    }

    /// Closes the reference pane window for a given parent window, if open.
    ///
    /// This closes the window without returning to docked mode. Use
    /// `returnReferencePaneToDock(for:)` to close and re-dock.
    ///
    /// - Parameter parentController: The browser window controller.
    func closeReferencePaneWindow(for parentController: RefraxWindowController) {
        let parentID = ObjectIdentifier(parentController.windowState)
        if let controller = referencePaneWindowControllers[parentID] {
            // Close window - the willCloseNotification observer will clean up tracking
            controller.window?.close()
        }
    }

    /// Closes the reference pane window and returns to docked mode.
    ///
    /// The inspector panel will expand to show the reference pane content.
    ///
    /// - Parameter parentController: The browser window controller.
    func returnReferencePaneToDock(for parentController: RefraxWindowController) {
        let parentID = ObjectIdentifier(parentController.windowState)
        if let controller = referencePaneWindowControllers[parentID] {
            controller.returnToDock()
        }
    }

    /// Returns whether a reference pane window exists for the given parent window.
    ///
    /// - Parameter parentController: The browser window controller.
    /// - Returns: True if a reference pane window is open for this parent.
    func hasReferencePaneWindow(for parentController: RefraxWindowController) -> Bool {
        let parentID = ObjectIdentifier(parentController.windowState)
        return referencePaneWindowControllers[parentID] != nil
    }

    /// Brings the reference pane window to front if it exists.
    ///
    /// - Parameter parentController: The browser window controller.
    /// - Returns: True if the window was brought to front, false if no window exists.
    @discardableResult
    func bringReferencePaneWindowToFront(for parentController: RefraxWindowController) -> Bool {
        let parentID = ObjectIdentifier(parentController.windowState)
        guard let controller = referencePaneWindowControllers[parentID],
              let window = controller.window else {
            return false
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    /// Cleans up tracking state for a reference pane window.
    ///
    /// Called when the reference pane window closes, either from user action or
    /// when the parent window closes.
    private func cleanupReferencePaneWindow(parentID: ObjectIdentifier) {
        referencePaneWindowControllers.removeValue(forKey: parentID)

        if let observer = referencePaneCloseObservers.removeValue(forKey: parentID) {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Glimpse Window

    /// Creates a Glimpse window for quick ephemeral browsing.
    ///
    /// Glimpse windows provide minimal UI (address bar + navigation only), no sidebar,
    /// and are designed for quick browsing tasks. They can be opened via:
    /// - Option+Enter from Command Lens
    /// - Option+Click on a link
    /// - Configured to receive external URLs
    ///
    /// ## Behavior
    ///
    /// - The page is not persisted to SwiftData
    /// - Shares WebPagePool with main windows
    /// - Can be transferred to any space via toolbar dropdown
    /// - Closing the window terminates the WebPage
    ///
    /// - Parameters:
    ///   - url: The URL to load in the Glimpse window.
    ///   - sourceController: Optional parent window to position relative to.
    /// - Returns: The created Glimpse window controller.
    @discardableResult
    func createGlimpseWindow(
        url: URL,
        relativeTo sourceController: RefraxWindowController? = nil,
    ) -> GlimpseController {
        // Get environment from active window or create minimal one
        guard let sourceController = sourceController ?? activeWindowController else {
            Logger.warning("Creating Glimpse window without environment source", category: Logger.tabs)
            // Create without showing - would need environment
            fatalError("Cannot create Glimpse window without an active window controller")
        }

        let controller = GlimpseController(
            url: url,
            environment: sourceController.environment,
            windowManager: self,
            tabManager: tabManager,
        )

        glimpseWindowControllers.append(controller)

        if let sourceWindow = sourceController.window {
            // Calculate size from source window's web content area
            var size = NSSize(width: 1_280, height: 720)
            let splitVC = sourceController.splitViewController
            if splitVC.splitViewItems.count > 1 {
                let contentFrame = splitVC.splitViewItems[1].viewController.view.frame
                size = NSSize(width: contentFrame.width, height: contentFrame.height)
            }

            controller.showWindow(
                size: size,
                relativeTo: sourceWindow,
            )
        } else {
            controller.showCentered()
        }

        return controller
    }

    /// Removes a Glimpse window from tracking.
    ///
    /// Called by the Glimpse window controller when it closes.
    func removeGlimpseWindow(_ controller: GlimpseController) {
        glimpseWindowControllers.removeAll { $0 === controller }
    }

    /// Closes all open Glimpse windows.
    ///
    /// Called during app termination or when clearing ephemeral state.
    func closeAllGlimpseWindows() {
        for controller in glimpseWindowControllers {
            controller.window?.close()
        }
        // Note: Controllers remove themselves via removeGlimpseWindow when closing
    }

    // MARK: - Reflected Windows

    /// Creates a reflected window for an existing WebPage.
    ///
    /// Reflected windows use the owner/portal mechanism to display web content.
    /// When the reflected window becomes key, it claims ownership of the WebPage's
    /// interactive WebView, and other windows automatically switch to portal mode.
    ///
    /// Unlike MirrorWindow which uses CAPortalLayer (and goes black when parent tab
    /// is not displayed), reflected windows remain live regardless of parent tab state.
    ///
    /// - Parameters:
    ///   - webPage: The WebPage to display in the reflected window.
    ///   - sourceController: Optional parent window to position relative to.
    /// - Returns: The created reflected window controller.
    @discardableResult
    func createReflectedWindow(
        for webPage: WebPage,
        relativeTo sourceController: RefraxWindowController? = nil,
    ) -> ReflectedViewController {
        guard let sourceController = sourceController ?? activeWindowController else {
            Logger.warning("Creating reflected window without environment source", category: Logger.tabs)
            fatalError("Cannot create reflected window without an active window controller")
        }

        let controller = webPage.createReflectedWindow(environment: sourceController.environment)
        controller.showRelativeTo(sourceController.window)

        return controller
    }
}

// MARK: - Constants

extension NSSize {
    static let defaultWindowSize = NSSize(width: 1_440, height: 1_080)
}
