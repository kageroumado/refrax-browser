import AppKit
import SwiftUI

/// Address bar button showing a key icon when there's a pending password save request.
///
/// This button appears after form submission when credentials are detected.
/// Clicking it opens the save password prompt popover.
///
/// Uses NSPopover with `.applicationDefined` behavior to prevent auto-dismiss on outside clicks.
/// The popover only closes when the user explicitly clicks a button (Save, Not Now, Never, etc.).
struct AddressBarSavePasswordButton: View {
    @Environment(AutoFillState.self) private var autoFillState

    @State private var popoverController: SavePasswordPopoverController?

    var body: some View {
        Button {
            togglePopover()
        } label: {
            Image(systemName: "key.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.appAccentColor)
        }
        .buttonStyle(.plain)
        .frame(width: Constants.AddressBar.buttonWidth, height: Constants.AddressBar.buttonWidth)
        .contentShape(Circle())
        .accessibilityIdentifier("addressbar-save-password")
        .accessibilityLabel("Save password")
        .background(PopoverAnchorView(controller: $popoverController, autoFillState: autoFillState))
        .onAppear {
            // Auto-show popover when button appears
            if autoFillState.pendingSaveRequest != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showPopover()
                }
            }
        }
        .onChange(of: autoFillState.pendingSaveRequest != nil) { _, hasPendingRequest in
            if hasPendingRequest {
                showPopover()
            } else {
                hidePopover()
            }
        }
    }

    private func togglePopover() {
        if popoverController?.isShown == true {
            hidePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        popoverController?.show()
    }

    private func hidePopover() {
        popoverController?.hide()
    }
}

// MARK: - Popover Anchor View

/// NSViewRepresentable that provides an anchor point for the NSPopover.
///
/// The view fills its parent's bounds so the popover can anchor to the button correctly.
private struct PopoverAnchorView: NSViewRepresentable {
    @Binding var controller: SavePasswordPopoverController?
    let autoFillState: AutoFillState

    func makeNSView(context _: Context) -> NSView {
        let view = PopoverAnchorNSView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        // Create controller if needed
        if controller == nil {
            let newController = SavePasswordPopoverController(
                anchorView: nsView,
                autoFillState: autoFillState,
            )
            DispatchQueue.main.async {
                controller = newController
            }
        } else {
            controller?.anchorView = nsView
        }
    }
}

/// Custom NSView that reports its actual bounds for correct popover positioning.
private final class PopoverAnchorNSView: NSView {
    override var isFlipped: Bool {
        true
    }
}

// MARK: - Popover Controller

/// Controller managing the NSPopover for save password prompts.
///
/// Uses `.applicationDefined` behavior to prevent auto-dismiss on outside clicks.
/// The popover only closes when explicitly dismissed via user action.
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

    func show() {
        guard let request = autoFillState.pendingSaveRequest else { return }

        // Close existing popover if any
        popover?.close()

        // Create the popover
        let newPopover = NSPopover()
        newPopover.behavior = .applicationDefined // Won't auto-close on outside click
        newPopover.animates = true
        newPopover.delegate = self

        // Create the content view with dismiss callback
        let contentView = SavePasswordPromptView(request: request)
            .environment(autoFillState)

        let hostingController = NSHostingController(rootView: contentView)
        newPopover.contentViewController = hostingController

        // Show the popover below the button
        // Use .minY because the anchor view uses flipped coordinates (y=0 at top)
        newPopover.show(
            relativeTo: anchorView.bounds,
            of: anchorView,
            preferredEdge: .minY,
        )

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

// MARK: - Button Style

/// Compact button style for address bar buttons.
///
/// Provides consistent sizing and hover state for all address bar buttons.
struct AddressBarButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: Constants.AddressBar.buttonWidth, height: Constants.AddressBar.buttonWidth)
            .background {
                Circle()
                    .fill(isHovered || configuration.isPressed ? Color.primary.opacity(0.1) : .clear)
            }
            .onHover { isHovered = $0 }
            .contentShape(Circle())
    }
}
