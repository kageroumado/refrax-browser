import AppKit
import SwiftUI

extension View {
    /// Anchors the save-password prompt to this view: it opens when a save request arrives,
    /// on appear if one is already waiting, and closes when the request is answered.
    ///
    /// `controller` is the prompt's popover, for a button that toggles it.
    func savePasswordPrompt(controller: Binding<SavePasswordPopoverController?>) -> some View {
        modifier(SavePasswordPromptModifier(controller: controller))
    }
}

private struct SavePasswordPromptModifier: ViewModifier {
    @Binding var controller: SavePasswordPopoverController?
    @Environment(AutoFillState.self) private var autoFillState

    func body(content: Content) -> some View {
        content
            .background(SavePasswordPopoverAnchor(controller: $controller, autoFillState: autoFillState))
            .onAppear {
                guard autoFillState.pendingSaveRequest != nil else { return }
                // The anchor creates its controller on the next turn of the run loop.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    controller?.offer()
                }
            }
            .onChange(of: autoFillState.pendingSaveRequest != nil) { _, hasPendingRequest in
                if hasPendingRequest {
                    controller?.offer()
                } else {
                    controller?.hide()
                }
            }
    }
}

// MARK: - Anchor

/// The view the prompt's popover points at; it fills the anchored view's bounds.
private struct SavePasswordPopoverAnchor: NSViewRepresentable {
    @Binding var controller: SavePasswordPopoverController?
    let autoFillState: AutoFillState

    func makeNSView(context _: Context) -> NSView {
        let view = FlippedAnchorView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        if let controller {
            controller.anchorView = nsView
        } else {
            let newController = SavePasswordPopoverController(anchorView: nsView, autoFillState: autoFillState)
            DispatchQueue.main.async {
                controller = newController
            }
        }
    }
}

/// Reports its bounds top-down so the popover's `.minY` edge is the anchor's bottom.
private final class FlippedAnchorView: NSView {
    override var isFlipped: Bool {
        true
    }
}

// MARK: - Popover Controller

/// The save-password prompt's popover.
///
/// It uses `.applicationDefined` behavior, so a click outside leaves it open; it closes only
/// when the person answers it (Save, Not Now, Never) or the request goes away.
final class SavePasswordPopoverController: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    var anchorView: NSView

    private let autoFillState: AutoFillState

    var isShown: Bool {
        popover?.isShown ?? false
    }

    init(anchorView: NSView, autoFillState: AutoFillState) {
        self.anchorView = anchorView
        self.autoFillState = autoFillState
        super.init()
    }

    func toggle() {
        if isShown {
            hide()
        } else {
            show()
        }
    }

    /// Opens the prompt unasked, in the key window only, so one request opens one prompt.
    func offer() {
        guard anchorView.window?.isKeyWindow == true else { return }
        show()
    }

    func show() {
        guard let request = autoFillState.pendingSaveRequest, anchorView.window != nil else { return }
        popover?.close()

        let newPopover = NSPopover()
        newPopover.behavior = .applicationDefined
        newPopover.animates = true
        newPopover.delegate = self
        newPopover.contentViewController = NSHostingController(rootView: SavePasswordPromptView(request: request).environment(autoFillState))
        newPopover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        popover = newPopover
    }

    func hide() {
        popover?.close()
        popover = nil
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_: Notification) {
        popover = nil
    }
}
