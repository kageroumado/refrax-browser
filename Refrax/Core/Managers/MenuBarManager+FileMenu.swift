import AppKit
import UniformTypeIdentifiers

// MARK: - File Menu

extension MenuBarManager {
    func createFileMenu() -> NSMenuItem {
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")

        // New Window
        let newWindowItem = NSMenuItem(
            title: "New Window",
            action: #selector(openNewWindow(_:)),
            keyEquivalent: "n",
        )
        newWindowItem.keyEquivalentModifierMask = [.command]
        newWindowItem.image = NSImage(systemSymbolName: "plus.rectangle.on.rectangle", accessibilityDescription: nil)
        newWindowItem.target = self
        fileMenu.addItem(newWindowItem)

        // New Tab
        let newTabItem = NSMenuItem(
            title: "Open Command Lens",
            action: #selector(openCommandLens(_:)),
            keyEquivalent: "t",
        )
        newTabItem.image = NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: nil)
        newTabItem.target = self
        fileMenu.addItem(newTabItem)

        fileMenu.addItem(.separator())

        // Open Location
        let openLocationItem = NSMenuItem(
            title: "Open Location…",
            action: #selector(openLocation(_:)),
            keyEquivalent: "l",
        )
        openLocationItem.image = NSImage(systemSymbolName: "location", accessibilityDescription: nil)
        openLocationItem.target = self
        fileMenu.addItem(openLocationItem)

        // Open File
        let openFileItem = NSMenuItem(
            title: "Open File…",
            action: #selector(openFile(_:)),
            keyEquivalent: "o",
        )
        openFileItem.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        openFileItem.target = self
        fileMenu.addItem(openFileItem)

        // Import from Another Browser
        let importBrowserItem = NSMenuItem(
            title: "Import from Another Browser…",
            action: #selector(importBrowserData(_:)),
            keyEquivalent: "",
        )
        importBrowserItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        importBrowserItem.target = self
        fileMenu.addItem(importBrowserItem)

        // Import Tabs & Groups
        let importTabsItem = NSMenuItem(
            title: "Import Tabs & Groups…",
            action: #selector(importTabsAndGroups(_:)),
            keyEquivalent: "",
        )
        importTabsItem.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: nil)
        importTabsItem.target = self
        fileMenu.addItem(importTabsItem)

        fileMenu.addItem(.separator())

        // Close Tab
        let closeTabItem = NSMenuItem(
            title: "Close Tab",
            action: #selector(closeTab(_:)),
            keyEquivalent: "w",
        )
        closeTabItem.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        closeTabItem.target = self
        fileMenu.addItem(closeTabItem)

        // Close Window
        let closeWindowItem = NSMenuItem(
            title: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w",
        )
        closeWindowItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(closeWindowItem)

        fileMenu.addItem(.separator())

        // Save As
        let saveAsItem = NSMenuItem(
            title: "Save As…",
            action: #selector(saveAs(_:)),
            keyEquivalent: "s",
        )
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        saveAsItem.image = NSImage(systemSymbolName: "arrow.up.document", accessibilityDescription: nil)
        saveAsItem.target = self
        fileMenu.addItem(saveAsItem)

        fileMenu.addItem(.separator())

        // Export submenu
        let exportMenuItem = NSMenuItem(title: "Export", action: nil, keyEquivalent: "")
        exportMenuItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        let exportMenu = NSMenu()

        let exportPDFItem = NSMenuItem(
            title: "Export as PDF…",
            action: #selector(exportAsPDF(_:)),
            keyEquivalent: "",
        )
        exportPDFItem.image = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: nil)
        exportPDFItem.target = self
        exportMenu.addItem(exportPDFItem)

        let exportWebArchiveItem = NSMenuItem(
            title: "Export as Web Archive…",
            action: #selector(exportAsWebArchive(_:)),
            keyEquivalent: "",
        )
        exportWebArchiveItem.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: nil)
        exportWebArchiveItem.target = self
        exportMenu.addItem(exportWebArchiveItem)

        exportMenu.addItem(.separator())

        let exportHistoryItem = NSMenuItem(
            title: "Export History…",
            action: #selector(exportHistory(_:)),
            keyEquivalent: "",
        )
        exportHistoryItem.image = NSImage(systemSymbolName: "clock.arrow.trianglehead.counterclockwise.rotate.90", accessibilityDescription: nil)
        exportHistoryItem.target = self
        exportMenu.addItem(exportHistoryItem)

        let exportTabsItem = NSMenuItem(
            title: "Export Tabs & Groups…",
            action: #selector(exportTabsAndGroups(_:)),
            keyEquivalent: "",
        )
        exportTabsItem.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: nil)
        exportTabsItem.target = self
        exportMenu.addItem(exportTabsItem)

        exportMenuItem.submenu = exportMenu
        fileMenu.addItem(exportMenuItem)

        fileMenu.addItem(.separator())

        // Print
        let printItem = NSMenuItem(
            title: "Print…",
            action: #selector(printPage(_:)),
            keyEquivalent: "p",
        )
        printItem.image = NSImage(systemSymbolName: "printer", accessibilityDescription: nil)
        printItem.target = self
        fileMenu.addItem(printItem)

        fileMenuItem.submenu = fileMenu
        return fileMenuItem
    }

    @objc
    func openNewWindow(_: Any?) {
        windowManager.createWindow()
    }

    @objc
    func openCommandLens(_: Any?) {
        windowManager.openCommandLens()
    }

    @objc
    func openLocation(_: Any?) {
        windowManager.openLocation()
    }

    @objc
    func openFile(_: Any?) {
        guard let controller = activeWindowController,
              let window = controller.window else { return }

        Task { @MainActor in
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = Self.webKitOpenableTypes
            panel.message = "Select files to open in Refrax"

            let response = await panel.beginSheetModal(for: window)
            guard response == .OK else { return }

            for (index, url) in panel.urls.enumerated() {
                controller.tabManager.createTab(url: url, makeActive: index == 0)
            }
        }
    }

    @objc
    func closeTab(_: Any?) {
        guard let controller = activeWindowController,
              let tab = controller.windowState.activeTab else { return }
        if tab.status == .liveFavorite {
            windowManager.tabManager.closeLiveFavoriteTab(tab)
            controller.windowState.clearActiveLiveFavorite()
        } else {
            windowManager.tabManager.closeTab(tab)
        }
    }

    @objc
    func saveAs(_: Any?) {
        guard let controller = activeWindowController,
              let webPage = controller.windowState.activeWebPage,
              let window = controller.window else { return }

        Task { @MainActor in
            await presentSaveAsPanel(for: webPage, in: window)
        }
    }

    /// Presents the Save As panel with format selection.
    private func presentSaveAsPanel(for webPage: WebPage, in window: NSWindow) async {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true

        let formatPicker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 25), pullsDown: false)
        formatPicker.addItems(withTitles: SaveAsFormat.allCases.map(\.title))

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        let label = NSTextField(labelWithString: "Format:")
        label.frame = NSRect(x: 0, y: 10, width: 50, height: 20)
        formatPicker.frame = NSRect(x: 55, y: 8, width: 200, height: 25)

        accessoryView.addSubview(label)
        accessoryView.addSubview(formatPicker)
        savePanel.accessoryView = accessoryView

        let defaultFormat = SaveAsFormat.pageSource
        savePanel.allowedContentTypes = [defaultFormat.contentType]
        savePanel.nameFieldStringValue = "\(webPage.tabPage.title)\(defaultFormat.fileExtension)"

        var currentFormat = defaultFormat
        let observation = NotificationCenter.default.addObserver(
            forName: NSMenu.didSendActionNotification,
            object: formatPicker.menu,
            queue: .main,
        ) { [weak savePanel] _ in
            MainActor.assumeIsolated {
                guard let savePanel,
                      let format = SaveAsFormat(rawValue: formatPicker.indexOfSelectedItem) else { return }
                currentFormat = format
                savePanel.allowedContentTypes = [format.contentType]
            }
        }

        defer { NotificationCenter.default.removeObserver(observation) }

        let response = await savePanel.beginSheetModal(for: window)
        guard response == .OK, let url = savePanel.url else { return }

        do {
            let data = try await exportData(for: currentFormat, webPage: webPage)
            try data.write(to: url)
        } catch {
            Logger.error("Failed to save page: \(error)", category: Logger.navigation)
        }
    }

    /// Exports data in the specified format.
    private func exportData(for format: SaveAsFormat, webPage: WebPage) async throws -> Data {
        switch format {
        case .pageSource:
            try await webPage.exportAsPageSource()
        case .webArchive:
            try await webPage.exportAsWebArchive()
        case .pdf:
            try await webPage.exportAsPDF()
        case .png:
            try await webPage.exportAsImage()
        }
    }

    @objc
    func printPage(_: Any?) {
        guard let webPage = activeWindowController?.windowState.activeWebPage else { return }
        webPage.printPage()
    }

    @objc
    func exportAsPDF(_: Any?) {
        guard let webPage = activeWindowController?.windowState.activeWebPage,
              let window = NSApp.keyWindow else { return }

        Task { @MainActor in
            do {
                let pdfData = try await webPage.exportAsPDF()

                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.pdf]
                savePanel.nameFieldStringValue = "\(webPage.tabPage.title).pdf"
                savePanel.canCreateDirectories = true

                let response = await savePanel.beginSheetModal(for: window)
                if response == .OK, let url = savePanel.url {
                    try pdfData.write(to: url)
                }
            } catch {
                Logger.error("Failed to export PDF: \(error)", category: Logger.navigation)
            }
        }
    }

    @objc
    func exportAsWebArchive(_: Any?) {
        guard let webPage = activeWindowController?.windowState.activeWebPage,
              let window = NSApp.keyWindow else { return }

        Task { @MainActor in
            do {
                let archiveData = try await webPage.exportAsWebArchive()

                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.webArchive]
                savePanel.nameFieldStringValue = "\(webPage.tabPage.title).webarchive"
                savePanel.canCreateDirectories = true

                let response = await savePanel.beginSheetModal(for: window)
                if response == .OK, let url = savePanel.url {
                    try archiveData.write(to: url)
                }
            } catch {
                Logger.error("Failed to export web archive: \(error)", category: Logger.navigation)
            }
        }
    }

    @objc
    func exportHistory(_: Any?) {
        windowManager.showHistoryExport()
    }

    @objc
    func exportTabsAndGroups(_: Any?) {
        guard let controller = activeWindowController,
              let space = controller.windowState.activeSpace,
              let window = controller.window else { return }

        Task { @MainActor in
            let export = SessionExport(space: space)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            guard let jsonData = try? encoder.encode(export) else {
                Logger.error("Failed to encode session export", category: Logger.navigation)
                return
            }

            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.json]
            savePanel.nameFieldStringValue = "\(space.name) - Tabs.json"
            savePanel.canCreateDirectories = true

            let response = await savePanel.beginSheetModal(for: window)
            if response == .OK, let url = savePanel.url {
                do {
                    try jsonData.write(to: url)
                } catch {
                    Logger.error("Failed to save tabs export: \(error)", category: Logger.navigation)
                }
            }
        }
    }

    @objc
    func importBrowserData(_: Any?) {
        guard let controller = activeWindowController else { return }
        controller.windowState.showsBrowserImport = true
    }

    @objc
    func importTabsAndGroups(_: Any?) {
        guard let controller = activeWindowController,
              let space = controller.windowState.activeSpace,
              let window = controller.window else { return }

        Task { @MainActor in
            let openPanel = NSOpenPanel()
            openPanel.allowedContentTypes = [.json]
            openPanel.allowsMultipleSelection = false
            openPanel.canChooseDirectories = false

            let response = await openPanel.beginSheetModal(for: window)
            guard response == .OK, let url = openPanel.url else { return }

            do {
                // Read file off main thread
                let data = try await Task.detached {
                    try Data(contentsOf: url)
                }.value

                // Decode on MainActor (SessionExport is MainActor-isolated)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let sessionExport = try decoder.decode(SessionExport.self, from: data)

                await importSession(sessionExport, into: space)
            } catch {
                Logger.error("Failed to import tabs: \(error)", category: Logger.navigation)
                await showImportError(in: window, error: error)
            }
        }
    }

    /// Imports a session export into the given space.
    private func importSession(_ export: SessionExport, into space: Space) async {
        guard let tabManager = windowManager.tabManager else { return }
        let groupManager = tabManager.groupManager

        // Process each exported space - for now we merge into current space
        for exportedSpace in export.spaces {
            // Create groups first (to get their IDs for tab assignment)
            var groupIDMap: [String: UUID] = [:] // name -> created group ID

            for exportedGroup in exportedSpace.groups {
                do {
                    let group = try groupManager.createGroup(
                        in: space,
                        name: exportedGroup.name,
                        color: exportedGroup.color,
                        iconName: exportedGroup.icon,
                        isPinned: exportedGroup.isPinned,
                    )
                    group.isCollapsed = exportedGroup.isCollapsed
                    groupIDMap[exportedGroup.name] = group.id

                    // Create tabs in this group
                    for exportedTab in exportedGroup.tabs {
                        guard let url = URL(string: exportedTab.url) else { continue }
                        let tab = tabManager.createTab(
                            url: url,
                            in: space,
                            groupID: group.id,
                            isPinned: exportedTab.isPinned,
                            makeActive: false,
                            loadImmediately: false,
                        )
                        tab.customName = exportedTab.customName
                        if !exportedTab.title.isEmpty, exportedTab.title != "New Tab" {
                            tab.activePage.title = exportedTab.title
                        }
                    }
                } catch {
                    Logger.error("Failed to create group '\(exportedGroup.name)': \(error)", category: Logger.navigation)
                }
            }

            // Create ungrouped tabs
            for exportedTab in exportedSpace.tabs {
                guard let url = URL(string: exportedTab.url) else { continue }
                let tab = tabManager.createTab(
                    url: url,
                    in: space,
                    isPinned: exportedTab.isPinned,
                    makeActive: false,
                    loadImmediately: false,
                )
                tab.customName = exportedTab.customName
                if !exportedTab.title.isEmpty, exportedTab.title != "New Tab" {
                    tab.activePage.title = exportedTab.title
                }
            }
        }
    }

    /// Content types that WebKit can render locally.
    private static let webKitOpenableTypes: [UTType] = [
        .html,
        .webArchive,
        .pdf,
        .png,
        .jpeg,
        .gif,
        .webP,
        .svg,
        .bmp,
        .ico,
        .tiff,
        .plainText,
        .xml,
        .json,
    ]

    /// Shows an error alert for failed imports.
    private func showImportError(in window: NSWindow, error: any Error) async {
        let alert = NSAlert()
        alert.messageText = "Import Failed"
        alert.informativeText = "Could not import tabs from the selected file. The file may be corrupted or in an unsupported format.\n\nError: \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        await alert.beginSheetModal(for: window)
    }
}

// MARK: - Save As Format

/// Available formats for Save As operation.
private enum SaveAsFormat: Int, CaseIterable {
    case pageSource
    case webArchive
    case pdf
    case png

    var title: String {
        switch self {
        case .pageSource: "Page Source"
        case .webArchive: "Web Archive"
        case .pdf: "PDF"
        case .png: "PNG"
        }
    }

    var fileExtension: String {
        switch self {
        case .pageSource: ".html"
        case .webArchive: ".webarchive"
        case .pdf: ".pdf"
        case .png: ".png"
        }
    }

    var contentType: UTType {
        switch self {
        case .pageSource: .html
        case .webArchive: .webArchive
        case .pdf: .pdf
        case .png: .png
        }
    }
}
