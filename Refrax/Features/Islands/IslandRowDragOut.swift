import AppKit
import SwiftUI

/// A row's drag that left the browser window, as a system drag: each tab is one item that
/// gives Finder a `.webloc`, other apps its address, and an island of this browser the tab
/// itself.
@MainActor
enum IslandRowDragOut {
    private enum Layout {
        /// How far each further tab's image sits under the one before it.
        static let stackOffset: CGFloat = 6
    }

    /// Whether `tab` has an address worth carrying out of the browser.
    static func carriesAddress(_ tab: Tab) -> Bool {
        let url = tab.activePage.url
        return !url.isBlank && (url.isWebURL || url.isFileURL)
    }

    /// Starts the system drag of `tabs` from `view` with `event`, the mouse-dragged event
    /// under way. Returns whether it started.
    @discardableResult
    static func begin(_ tabs: [Tab], from view: NSView, event: NSEvent, islands: IslandController) -> Bool {
        guard event.type == .leftMouseDragged, let window = view.window else { return false }
        let point = view.convert(event.locationInWindow, from: nil)
        let items = tabs.filter(carriesAddress).enumerated().map { index, tab in
            let item = NSDraggingItem(pasteboardWriter: TabDragPromise(tabID: tab.id, url: tab.activePage.url, title: tab.displayTitle))
            let image = label(for: tab, scale: window.backingScaleFactor)
            let origin = CGPoint(x: point.x - image.size.width / 2, y: point.y - image.size.height / 2 - CGFloat(index) * Layout.stackOffset)
            item.setDraggingFrame(CGRect(origin: origin, size: image.size), contents: image)
            return item
        }
        guard !items.isEmpty else { return false }
        let source = IslandRowDragSource(islands: islands)
        islands.dragOutSource = source
        let session = view.beginDraggingSession(with: items, event: event, source: source)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .stack
        return true
    }

    /// The tab as the drag shows it: its favicon and title on a capsule.
    private static func label(for tab: Tab, scale: CGFloat) -> NSImage {
        let renderer = ImageRenderer(content: DragOutLabel(title: tab.displayTitle, favicon: tab.activePage.faviconData.flatMap(NSImage.init(data:))))
        renderer.scale = scale
        return renderer.nsImage ?? NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
    }
}

/// A dragged tab's image: favicon and title on an opaque capsule, which an image renderer
/// draws where glass would not render.
private struct DragOutLabel: View {
    let title: String
    let favicon: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let favicon {
                    Image(nsImage: favicon).resizable().scaledToFit()
                } else {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: 220, minHeight: 28)
        .fixedSize()
        .background(Color(nsColor: .windowBackgroundColor), in: .capsule)
    }
}

/// Answers the system for a row's drag: a copy anywhere outside the browser, a move within
/// it, which only an island takes; and lets the islands know when it ends.
final class IslandRowDragSource: NSObject, NSDraggingSource {
    private weak var islands: IslandController?

    init(islands: IslandController) {
        self.islands = islands
    }

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : .move
    }

    func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation _: NSDragOperation) {
        islands?.endDragOut()
    }
}

/// One dragged tab on the pasteboard: a promised `.webloc` named after its title, its
/// address as a URL and as text, and its identity for an island to take it back.
///
/// Everything is copied at creation: the pasteboard asks for it later, on another thread,
/// when the tab may be gone.
final nonisolated class TabDragPromise: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
    let tabID: UUID
    let url: URL
    let title: String

    init(tabID: UUID, url: URL, title: String) {
        self.tabID = tabID
        self.url = url
        self.title = title
        super.init()
        fileType = WeblocFile.typeIdentifier
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [IslandPasteboard.tabIDs, .URL, .string]
    }

    override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        switch type {
        case IslandPasteboard.tabIDs, .URL, .string: []
        default: super.writingOptions(forType: type, pasteboard: pasteboard)
        }
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case IslandPasteboard.tabIDs: tabID.uuidString
        case .URL, .string: url.absoluteString
        default: super.pasteboardPropertyList(forType: type)
        }
    }

    func filePromiseProvider(_: NSFilePromiseProvider, fileNameForType _: String) -> String {
        WeblocFile.filename(title: title, url: url)
    }

    func filePromiseProvider(_: NSFilePromiseProvider, writePromiseTo destination: URL, completionHandler: @escaping ((any Error)?) -> Void) {
        do {
            try WeblocFile.data(for: url).write(to: destination)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}
