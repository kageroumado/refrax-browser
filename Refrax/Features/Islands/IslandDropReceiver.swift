import AppKit
import SwiftUI

/// Pasteboard types the islands write and read for a row dragged out of an island.
nonisolated enum IslandPasteboard {
    /// The dragged tabs' identities, one UUID per line.
    static let tabIDs = NSPasteboard.PasteboardType("com.refrax.tab-id")

    /// Every type a drop on an island can bring.
    static let acceptedTypes: [NSPasteboard.PasteboardType] = [
        tabIDs, .URL, .fileURL, .string, NSPasteboard.PasteboardType("NSFilenamesPboardType"),
    ]

    /// Reads what a drop brings from `pasteboard`.
    static func payload(from pasteboard: NSPasteboard) -> IslandDropPayload {
        let tabIDs = (pasteboard.pasteboardItems ?? []).compactMap { $0.string(forType: tabIDs) }
            .flatMap { $0.split(separator: "\n") }
            .compactMap { UUID(uuidString: String($0)) }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        let strings = pasteboard.string(forType: .string).map { [$0] } ?? []
        return IslandDropPayload(tabIDs: tabIDs, urls: urls, strings: strings)
    }
}

/// Takes links, files, text, and rows dragged from another window onto an island: lies over
/// the island's rows, lets every click through, and hands each drop to the islands with the
/// pointer in the layer's coordinates, where the row under it is found.
struct IslandDropReceiver: NSViewRepresentable {
    @Environment(IslandController.self) private var islands

    func makeNSView(context _: Context) -> IslandDropReceiverView {
        let view = IslandDropReceiverView()
        view.islands = islands
        return view
    }

    func updateNSView(_ view: IslandDropReceiverView, context _: Context) {
        view.islands = islands
    }
}

/// The AppKit drop destination behind ``IslandDropReceiver``.
final class IslandDropReceiverView: NSView {
    weak var islands: IslandController?
    /// What the drop under way brings, read once as it enters.
    private var payload = IslandDropPayload()

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(IslandPasteboard.acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Clicks, hovers, and drags of the rows go to the SwiftUI views beneath; drag
    /// destinations are found by their registered types.
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        payload = IslandPasteboard.payload(from: sender.draggingPasteboard)
        return update(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        update(sender)
    }

    override func draggingExited(_: (any NSDraggingInfo)?) {
        islands?.endExternalDrop()
    }

    override func prepareForDragOperation(_: any NSDraggingInfo) -> Bool {
        !payload.isEmpty
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let islands, let point = layerPoint(sender.draggingLocation) else { return false }
        return islands.performDrop(payload, at: point)
    }

    override func draggingEnded(_: any NSDraggingInfo) {
        payload = IslandDropPayload()
        islands?.endExternalDrop()
    }

    private func update(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard !payload.isEmpty, let islands, let point = layerPoint(sender.draggingLocation),
              islands.updateExternalDrop(at: point) else { return [] }
        return payload.tabIDs.isEmpty ? .copy : .move
    }

    /// A point in the window, in the islands layer's coordinates: the content view's, with the
    /// origin at the top left.
    private func layerPoint(_ locationInWindow: NSPoint) -> CGPoint? {
        guard let content = window?.contentView else { return nil }
        let local = content.convert(locationInWindow, from: nil)
        return CGPoint(x: local.x, y: content.isFlipped ? local.y : content.bounds.height - local.y)
    }
}
