import AppKit
import SwiftUI

/// Invisible NSView that acts as the source for AppKit drag sessions.
///
/// This view is placed in the sidebar's view hierarchy but has no visual presence.
/// When the DragCoordinator detects that a SwiftUI drag has moved outside the sidebar
/// bounds, it triggers a handoff to this view which creates an `NSDraggingSession`.
///
/// ## Handoff Sequence
///
/// 1. SwiftUI gesture calls `updateDrag()` with cursor outside sidebar
/// 2. Coordinator sets `handoffPhase = .transitioning`
/// 3. Coordinator calls `beginAppKitDrag()` on this view
/// 4. This view creates `NSDraggingItem`s and calls `beginDraggingSession`
/// 5. AppKit calls `willBeginAt` → coordinator hides SwiftUI overlay, sets `.external`
/// 6. User completes or cancels drag
/// 7. AppKit calls `endedAt` → coordinator resets all state
///
/// ## Thread Safety
///
/// All interactions happen on the main thread (required by both SwiftUI and AppKit).
struct SidebarDragSourceView: NSViewRepresentable {
    /// The drag coordinator that manages drag state.
    var coordinator: Sidebar.DragCoordinator

    func makeNSView(context _: Context) -> DragSourceNSView {
        let view = DragSourceNSView()
        view.dragCoordinator = coordinator
        // Register this view with the coordinator for handoff triggers
        coordinator.dragSourceView = view
        return view
    }

    func updateNSView(_ nsView: DragSourceNSView, context _: Context) {
        nsView.dragCoordinator = coordinator
        // Keep the reference updated
        coordinator.dragSourceView = nsView
    }

    static func dismantleNSView(_ nsView: DragSourceNSView, coordinator _: ()) {
        // Clear the reference when view is removed
        nsView.dragCoordinator?.dragSourceView = nil
    }
}

/// The actual NSView that implements NSDraggingSource.
///
/// This class is owned by the NSViewRepresentable and serves as the source
/// for AppKit drag sessions initiated during SwiftUI→AppKit handoff.
final class DragSourceNSView: NSView {
    /// Reference to the drag coordinator (set by the representable).
    unowned var dragCoordinator: Sidebar.DragCoordinator!

    /// The most recent mouse event (captured for creating drag sessions).
    ///
    /// AppKit's `beginDraggingSession` requires the initiating mouse event.
    /// Captured via local event monitor since this view has no size.
    private var lastMouseEvent: NSEvent?

    /// Strong reference to pasteboard writer to keep it alive during drag.
    private var activePasteboardWriter: DragPasteboardWriter?

    /// Reference to active drag session for modifying drag image on re-entry.
    private var activeDraggingSession: NSDraggingSession?

    /// Local event monitor for capturing mouse events.
    ///
    /// Since this view is 0x0 and doesn't receive hit tests, we use a local
    /// event monitor to capture mouse events for use in `beginDraggingSession`.
    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installEventMonitor()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        removeEventMonitor()
    }

    // MARK: - Event Monitor

    /// Install a local event monitor to capture mouse events.
    ///
    /// This is necessary because the view is 0x0 and doesn't receive
    /// direct mouse events. The monitor captures leftMouseDragged events
    /// which are used as the initiating event for `beginDraggingSession`.
    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged],
        ) { [weak self] event in
            self?.lastMouseEvent = event
            return event
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Public Interface

    /// Begin an AppKit drag session, taking over from the SwiftUI gesture.
    ///
    /// Called by the DragCoordinator when it detects the cursor has left the sidebar.
    /// This method creates the appropriate pasteboard items and drag image, then
    /// starts an `NSDraggingSession`.
    ///
    /// - Parameters:
    ///   - items: The items being dragged
    ///   - image: Pre-rendered drag image from DragImageRenderer
    ///   - frame: Frame for the drag image in SwiftUI global coordinates (top-left origin)
    func beginAppKitDrag(
        items: [Sidebar.DragCoordinator.DraggedItem],
        image: NSImage,
        frame _: CGRect,
    ) {
        guard let event = lastMouseEvent ?? NSApp.currentEvent else {
            // No event available - cannot start drag session
            // Restore to internal phase
            MainActor.assumeIsolated {
                dragCoordinator.handoffPhase = .internal
            }
            return
        }

        // Create pasteboard writer for URL and internal type data
        let pasteboardWriter = DragPasteboardWriter(items: items)
        activePasteboardWriter = pasteboardWriter

        // Build dragging items - exactly one per logical item being dragged.
        // IMPORTANT: macOS shows a count badge based on the number of NSDraggingItems.
        // Previously we created separate items for file promise providers, which caused
        // "(2)" badge when dragging just 1 tab. Now we use only the pasteboard writer.
        //
        // Note: Finder creates .webloc files from URL pasteboard data automatically,
        // so explicit file promise providers aren't needed for basic functionality.

        // Position the drag image centered on the current mouse location.
        // Using the mouse position directly ensures seamless transition from SwiftUI overlay.
        // The `frame` parameter is ignored - we use mouse position for accuracy.
        let mouseLocation = event.locationInWindow
        let imageFrame = NSRect(
            x: mouseLocation.x - image.size.width / 2,
            y: mouseLocation.y - image.size.height / 2,
            width: image.size.width,
            height: image.size.height,
        )

        // Create exactly ONE NSDraggingItem per logical item
        // Contains: URLs, strings, and internal Refrax types for re-entry detection
        let primaryItem = NSDraggingItem(pasteboardWriter: pasteboardWriter.createPasteboardItem())
        primaryItem.setDraggingFrame(imageFrame, contents: image)

        // Start the drag session
        let session = beginDraggingSession(with: [primaryItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .default

        // Store reference for re-entry handling
        activeDraggingSession = session
    }

    /// Hide the AppKit drag image when re-entering the sidebar.
    ///
    /// Called by the drop receiver when a re-entry is detected. This allows
    /// the SwiftUI overlay to take visual priority while still completing
    /// the AppKit drag session for proper drop handling.
    func hideDragImage() {
        guard let session = activeDraggingSession else { return }

        // Enumerate dragging items and set their image to transparent
        // This effectively hides the AppKit drag representation
        session.enumerateDraggingItems(
            options: [],
            for: nil,
            classes: [NSPasteboardItem.self],
            searchOptions: [:],
        ) { draggingItem, _, _ in
            // Set to a 1x1 transparent image - effectively invisible
            let transparentImage = NSImage(size: NSSize(width: 1, height: 1))
            draggingItem.setDraggingFrame(
                NSRect(x: draggingItem.draggingFrame.midX, y: draggingItem.draggingFrame.midY, width: 1, height: 1),
                contents: transparentImage,
            )
        }
    }

    /// Restore the AppKit drag image when exiting re-entry.
    ///
    /// Called by the drop receiver when the cursor leaves the sidebar during
    /// re-entry. Re-renders the current overlay and sets it on the drag session.
    func restoreDragImage() {
        guard let session = activeDraggingSession else { return }

        // Re-render the current overlay
        guard let image = DragImageRenderer.renderCurrentOverlay(from: dragCoordinator) else { return }

        // Get current mouse location for positioning
        guard let event = lastMouseEvent ?? NSApp.currentEvent else { return }
        let mouseLocation = event.locationInWindow
        let imageFrame = NSRect(
            x: mouseLocation.x - image.size.width / 2,
            y: mouseLocation.y - image.size.height / 2,
            width: image.size.width,
            height: image.size.height,
        )

        // Restore the image on the dragging items
        session.enumerateDraggingItems(
            options: [],
            for: nil,
            classes: [NSPasteboardItem.self],
            searchOptions: [:],
        ) { draggingItem, _, _ in
            draggingItem.setDraggingFrame(imageFrame, contents: image)
        }
    }
}

// MARK: - NSDraggingSource

extension DragSourceNSView: NSDraggingSource {
    func draggingSession(
        _: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext,
    ) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            // External drops (Finder, TextEdit, Safari, etc.) - always copy
            // Returning .move here would signal that the source expects deletion
            return .copy
        case .withinApplication:
            // Internal drops (re-entry to sidebar) - allow move semantics
            return .move
        @unknown default:
            return .copy
        }
    }

    func draggingSession(
        _: NSDraggingSession,
        willBeginAt _: NSPoint,
    ) {
        // Session has officially started - NOW hide the SwiftUI overlay
        // This is the safe point because the AppKit drag image is visible
        MainActor.assumeIsolated {
            dragCoordinator.handoffPhase = .external

            // Record when we entered external phase (for re-entry debouncing)
            dragCoordinator.externalPhaseStartTime = CACurrentMediaTime()

            // Clear the visual state to hide SwiftUI overlay
            // The ghostState preserves what we need for re-entry
            dragCoordinator.itemPushOffsets.removeAll()
        }
    }

    func draggingSession(
        _: NSDraggingSession,
        endedAt _: NSPoint,
        operation _: NSDragOperation,
    ) {
        // Clean up references
        activePasteboardWriter = nil
        activeDraggingSession = nil

        // Reset coordinator state
        MainActor.assumeIsolated {
            // Clear ghost state - drag is complete
            dragCoordinator.ghostState = nil

            // Full reset to clean state
            dragCoordinator.reset()
        }
    }

    func draggingSession(
        _: NSDraggingSession,
        movedTo _: NSPoint,
    ) {
        // Optional: Could be used to detect re-entry to sidebar
        // For now, re-entry will be handled by NSDraggingDestination on the sidebar
    }
}
