import AppKit
import UniformTypeIdentifiers

// MARK: - Download and Save Page As

extension WebPage {
    /// The page shows a file of its own, a PDF or an image, at a web address it can be
    /// fetched from again.
    var showsDownloadableFile: Bool {
        guard let scheme = url?.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return isDisplayingPDF || isDisplayingStandaloneImage
    }

    /// Downloads the file the page shows into its space's download folder, where the File
    /// Island lists it.
    func downloadShownFile() {
        guard showsDownloadableFile, let url, let downloadManager else { return }
        let space = tabPage.tab?.space
        let title = title
        let dataStore = websiteDataStore
        Task(name: "Download the page's file") {
            do {
                _ = try await downloadManager.startDownload(
                    from: url,
                    originatingURL: url,
                    originatingTitle: title,
                    dataStore: dataStore,
                    customDownloadPath: space?.customDownloadPath,
                    spaceID: space?.id,
                    spaceName: space?.name,
                    colorTag: space?.downloadColorTag,
                )
            } catch {
                Logger.error("Page download failed: \(error)", category: Logger.downloads)
            }
        }
    }

    /// Asks where to save the page and in which format, then writes it there.
    func presentSavePanel(in window: NSWindow) async {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true

        let defaultFormat: SavePageFormat = if isDisplayingPDF {
            .pdf
        } else if isDisplayingStandaloneImage {
            .png
        } else {
            .webArchive
        }

        let formatPicker = NSPopUpButton(frame: NSRect(x: 55, y: 8, width: 200, height: 25), pullsDown: false)
        formatPicker.addItems(withTitles: SavePageFormat.allCases.map(\.title))
        formatPicker.selectItem(at: defaultFormat.rawValue)

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        let label = NSTextField(labelWithString: "Format:")
        label.frame = NSRect(x: 0, y: 10, width: 50, height: 20)
        accessoryView.addSubview(label)
        accessoryView.addSubview(formatPicker)
        savePanel.accessoryView = accessoryView

        savePanel.allowedContentTypes = [defaultFormat.contentType]
        savePanel.nameFieldStringValue = "\(savedFileStem)\(defaultFormat.fileExtension)"

        var currentFormat = defaultFormat
        let observation = NotificationCenter.default.addObserver(
            forName: NSMenu.didSendActionNotification,
            object: formatPicker.menu,
            queue: .main,
        ) { [weak savePanel] _ in
            MainActor.assumeIsolated {
                guard let savePanel,
                      let format = SavePageFormat(rawValue: formatPicker.indexOfSelectedItem) else { return }
                currentFormat = format
                savePanel.allowedContentTypes = [format.contentType]
            }
        }
        defer { NotificationCenter.default.removeObserver(observation) }

        let response = await savePanel.beginSheetModal(for: window)
        guard response == .OK, let destination = savePanel.url else { return }

        do {
            let data = try await savedData(as: currentFormat)
            try data.write(to: destination)
        } catch {
            Logger.error("Failed to save page: \(error)", category: Logger.navigation)
        }
    }

    /// The page title, or the file name the address ends in, as a file name without extension.
    private var savedFileStem: String {
        let name = title.isEmpty ? (url?.deletingPathExtension().lastPathComponent ?? "Page") : title
        return FilenameUtilities.sanitize(name)
    }

    private func savedData(as format: SavePageFormat) async throws -> Data {
        switch format {
        case .webArchive: try await exportAsWebArchive()
        case .pageSource: try await exportAsPageSource()
        case .pdf: try await exportAsPDF()
        case .png: try await exportAsImage()
        }
    }
}

/// The formats Save Page As… writes, in the order its format menu lists them.
private enum SavePageFormat: Int, CaseIterable {
    case webArchive
    case pageSource
    case pdf
    case png

    var title: String {
        switch self {
        case .webArchive: "Web Archive"
        case .pageSource: "Page Source"
        case .pdf: "PDF"
        case .png: "PNG"
        }
    }

    var fileExtension: String {
        switch self {
        case .webArchive: ".webarchive"
        case .pageSource: ".html"
        case .pdf: ".pdf"
        case .png: ".png"
        }
    }

    var contentType: UTType {
        switch self {
        case .webArchive: .webArchive
        case .pageSource: .html
        case .pdf: .pdf
        case .png: .png
        }
    }
}
