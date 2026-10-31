import AppKit
import Foundation

/// The page menu's actions, bound to one page: copy, share, download and save, zoom,
/// screenshots, recording, Calm, and extension page actions. The page card builds one from its environment and
/// hands it to ``PageMenuContent``.
struct PageMenuActions {
    /// The live page, when it has one; the window screenshot and the copy actions work without it.
    let webPage: WebPage?
    let url: URL?
    let windowState: WindowState
    let sharing: SharingCoordinator
    let screenshots: ScreenshotCoordinator
    let recording: RecordingCoordinator
    let downloads: DownloadManager
    let extensions: ExtensionManager
    let siteSettings: SiteSettingsManager
    let pagePool: WebPagePool

    // MARK: - Page state

    var currentZoom: Int {
        webPage?.currentZoom ?? 100
    }

    var isPageCalmed: Bool {
        url.map { siteSettings.isCalmPage(for: $0) } ?? false
    }

    /// The page shows a PDF or an image that Download can fetch into the download folder.
    var canDownload: Bool {
        webPage?.showsDownloadableFile ?? false
    }

    /// The actions of the extensions running in the page's tab, with their badges.
    var extensionActions: [PageMenuExtension] {
        extensions.actionEntries(for: webPage?.tabPage.tab).map { entry in
            PageMenuExtension(
                id: entry.id,
                name: entry.appearance.label.isEmpty ? entry.name : entry.appearance.label,
                icon: entry.icon,
                badgeText: entry.appearance.badgeText,
                isEnabled: entry.appearance.isEnabled,
            )
        }
    }

    // MARK: - Actions

    func setZoom(_ zoom: Int) {
        webPage?.setZoom(zoom)
    }

    /// Copies the page address with its tracking parameters removed.
    func copyCleanURL() {
        guard let url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.removingTrackingParameters().absoluteString, forType: .string)
    }

    /// Copies the page as a Markdown link: `[Title](URL)`.
    func copyAsMarkdown() {
        guard let url else { return }
        let cleanURL = url.removingTrackingParameters()
        let title = webPage?.title ?? cleanURL.host ?? "Link"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("[\(title)](\(cleanURL.absoluteString))", forType: .string)
    }

    /// Shares the page address through the system share sheet.
    func share() {
        guard let url else { return }
        sharing.shareURL(url.removingTrackingParameters(), title: webPage?.title)
    }

    /// Downloads the PDF or image the page shows, so it appears in the File Island.
    func download() {
        webPage?.downloadShownFile()
    }

    /// Asks where to save the page and in which format.
    func savePageAs() {
        guard let webPage, let window = windowState.window else { return }
        Task(name: "Save page as") {
            await webPage.presentSavePanel(in: window)
        }
    }

    /// Captures the page, or the whole window for ``ScreenshotMode/window``.
    func takeScreenshot(mode: ScreenshotMode) {
        let window = windowState.window
        let saveDirectory = downloads.downloadDirectory(for: webPage?.tabPage.tab?.space?.customDownloadPath)

        if mode == .window {
            Task(name: "Capture window screenshot") {
                // Popovers and menus finish dismissing before the window is captured.
                try? await Task.sleep(for: .milliseconds(500))
                let result = await screenshots.captureWindow(window: window, saveDirectory: saveDirectory)
                if case let .failed(error) = result {
                    Logger.error("Screenshot failed: \(error)", category: Logger.navigation)
                }
            }
            return
        }

        guard let webPage else { return }
        Task(name: "Capture page screenshot") {
            let result: ScreenshotResult = switch mode {
            case .fullPage:
                await screenshots.captureFullPage(webPage: webPage, in: window, saveDirectory: saveDirectory)
            case .visibleArea:
                await screenshots.captureVisibleArea(webPage: webPage, in: window, saveDirectory: saveDirectory)
            case .selection:
                await screenshots.captureSelectedElement(webPage: webPage, in: window, saveDirectory: saveDirectory)
            case .window:
                preconditionFailure("Window capture returns above")
            }
            if case let .failed(error) = result {
                Logger.error("Screenshot failed: \(error)", category: Logger.navigation)
            }
        }
    }

    /// Starts recording the page's tab into the space's download folder.
    func startRecording() {
        guard let webPage else { return }
        let saveDirectory = downloads.downloadDirectory(for: webPage.tabPage.tab?.space?.customDownloadPath)
        recording.startRecording(webPage: webPage, in: windowState.window, saveDirectory: saveDirectory)
    }

    func stopRecording() {
        Task(name: "Stop tab recording") {
            _ = await recording.stopRecording()
        }
    }

    /// Performs the extension's action in the page's tab; its popup opens over the page card.
    func performExtensionAction(_ contextID: String) {
        extensions.performAction(contextID: contextID, in: webPage?.tabPage.tab, anchor: nil)
    }

    /// Toggles Calm for the page's domain and applies it to every live page of that domain.
    func toggleCalmPage() {
        guard let url, let host = url.host else { return }
        let calmed = siteSettings.toggleCalmPage(for: url)
        pagePool.applyCalm(calmed, toHost: host)
    }
}
