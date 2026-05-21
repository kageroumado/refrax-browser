import AppKit
import SwiftUI

/// AppKit-based drag source for shelf items.
///
/// SwiftUI's `.draggable()` with `Transferable` doesn't properly support custom filenames -
/// receivers see the internal UUID-based storage filename instead of the display name.
/// This wrapper uses AppKit's `NSDraggingSource` to properly expose filenames.
struct ShelfDragSource<Content: View>: NSViewRepresentable {
    let item: ShelfItem
    let storagePath: URL
    let content: Content

    init(item: ShelfItem, storagePath: URL, @ViewBuilder content: () -> Content) {
        self.item = item
        self.storagePath = storagePath
        self.content = content()
    }

    func makeNSView(context _: Context) -> DragSourceView<Content> {
        DragSourceView(item: item, storagePath: storagePath, content: content)
    }

    func updateNSView(_ nsView: DragSourceView<Content>, context _: Context) {
        nsView.item = item
        nsView.storagePath = storagePath
        nsView.updateContent(content)
    }
}

/// NSView subclass that hosts SwiftUI content and acts as a drag source.
final class DragSourceView<Content: View>: NSView, NSDraggingSource {
    var item: ShelfItem
    var storagePath: URL
    private var hostingView: NSHostingView<Content>

    init(item: ShelfItem, storagePath: URL, content: Content) {
        self.item = item
        self.storagePath = storagePath
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
    required init?(coder _: NSCoder) {
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
                // Click without drag - pass through
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

        // Create dragging items
        let draggingItems = createDraggingItems()
        guard !draggingItems.isEmpty else { return }

        for draggingItem in draggingItems {
            draggingItem.setDraggingFrame(bounds, contents: snapshot())
        }

        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    // MARK: - Dragging Item Creation

    private func createDraggingItems() -> [NSDraggingItem] {
        switch item.type {
        case .text:
            createTextDraggingItems()
        case .alias:
            createAliasDraggingItems()
        case .image, .file:
            createFileDraggingItems()
        }
    }

    private func createTextDraggingItems() -> [NSDraggingItem] {
        guard let data = try? Data(contentsOf: storagePath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let text = plist["public.utf8-plain-text"] as? String else {
            return []
        }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(text, forType: .string)
        return [NSDraggingItem(pasteboardWriter: pasteboardItem)]
    }

    private func createAliasDraggingItems() -> [NSDraggingItem] {
        guard let bookmarkData = try? Data(contentsOf: storagePath) else { return [] }

        var isStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale,
        ) else {
            return []
        }

        // For aliases, use the resolved file directly (it has the correct name)
        return [NSDraggingItem(pasteboardWriter: resolvedURL as NSURL)]
    }

    private func createFileDraggingItems() -> [NSDraggingItem] {
        // Create a temporary copy with the correct display name
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RefraxDrag-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let destURL = tempDir.appendingPathComponent(item.displayName)
            try FileManager.default.copyItem(at: storagePath, to: destURL)

            // Schedule cleanup after a delay (drag should be complete by then)
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                try? FileManager.default.removeItem(at: tempDir)
            }

            return [NSDraggingItem(pasteboardWriter: destURL as NSURL)]
        } catch {
            // Fallback to storage path if copy fails
            return [NSDraggingItem(pasteboardWriter: storagePath as NSURL)]
        }
    }

    // MARK: - Snapshot

    private func snapshot() -> NSImage {
        let image = NSImage(size: bounds.size)
        guard let bitmapRep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return image
        }
        cacheDisplay(in: bounds, to: bitmapRep)
        image.addRepresentation(bitmapRep)
        return image
    }

    // MARK: - NSDraggingSource

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation _: NSDragOperation) {
        // Drag ended - cleanup handled by delayed dispatch above
    }
}
