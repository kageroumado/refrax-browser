import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// AppKit-based drag source for screenshot preview images.
///
/// Wraps SwiftUI content in an NSView that acts as an NSDraggingSource.
/// Provides the screenshot as PNG data on the pasteboard, compatible with
/// web page drop zones, other apps, and Finder.
///
/// The drag source also handles swipe-to-dismiss: dragging right beyond
/// a threshold dismisses the preview instead of starting a file drag.
struct ScreenshotDragSource<Content: View>: NSViewRepresentable {
    let image: NSImage
    let imageData: Data
    let savedURL: URL?
    let onDragStarted: () -> Void
    let onDragEnded: (Bool) -> Void
    let content: Content

    init(
        image: NSImage,
        imageData: Data,
        savedURL: URL?,
        onDragStarted: @escaping () -> Void,
        onDragEnded: @escaping (Bool) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.image = image
        self.imageData = imageData
        self.savedURL = savedURL
        self.onDragStarted = onDragStarted
        self.onDragEnded = onDragEnded
        self.content = content()
    }

    func makeNSView(context: Context) -> ScreenshotDragSourceView<Content> {
        ScreenshotDragSourceView(
            image: image,
            imageData: imageData,
            savedURL: savedURL,
            onDragStarted: onDragStarted,
            onDragEnded: onDragEnded,
            content: content
        )
    }

    func updateNSView(_ nsView: ScreenshotDragSourceView<Content>, context: Context) {
        nsView.image = image
        nsView.imageData = imageData
        nsView.savedURL = savedURL
        nsView.updateContent(content)
    }
}

final class ScreenshotDragSourceView<Content: View>: NSView, NSDraggingSource {
    var image: NSImage
    var imageData: Data
    var savedURL: URL?
    var onDragStarted: () -> Void
    var onDragEnded: (Bool) -> Void
    private var hostingView: NSHostingView<Content>

    init(
        image: NSImage,
        imageData: Data,
        savedURL: URL?,
        onDragStarted: @escaping () -> Void,
        onDragEnded: @escaping (Bool) -> Void,
        content: Content
    ) {
        self.image = image
        self.imageData = imageData
        self.savedURL = savedURL
        self.onDragStarted = onDragStarted
        self.onDragEnded = onDragEnded
        self.hostingView = NSHostingView(rootView: content)

        super.init(frame: .zero)

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateContent(_ content: Content) {
        hostingView.rootView = content
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        let startLocation = convert(event.locationInWindow, from: nil)

        // Wait for drag threshold
        var dragStarted = false
        while true {
            guard let nextEvent = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) else {
                break
            }

            if nextEvent.type == .leftMouseUp {
                super.mouseDown(with: event)
                return
            }

            let currentLocation = convert(nextEvent.locationInWindow, from: nil)
            let distance = hypot(currentLocation.x - startLocation.x, currentLocation.y - startLocation.y)

            if distance > 3 {
                dragStarted = true
                break
            }
        }

        guard dragStarted else { return }

        onDragStarted()

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(imageData, forType: .png)

        if let tiffData = image.tiffRepresentation {
            pasteboardItem.setData(tiffData, forType: .tiff)
        }

        if let url = savedURL {
            pasteboardItem.setString(url.absoluteString, forType: .fileURL)
        }

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)

        let dragImage = NSImage(size: bounds.size)
        dragImage.lockFocus()
        image.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: 0.8
        )
        dragImage.unlockFocus()
        draggingItem.setDraggingFrame(bounds, contents: dragImage)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    // MARK: - NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .outsideApplication ? .copy : .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        MainActor.assumeIsolated {
            onDragEnded(operation != [])
        }
    }
}
