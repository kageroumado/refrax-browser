import AppKit
import SwiftUI

/// Tracks the native menu's lifetime so releasing Control preserves its actions.
struct ControlIslandTabMenuButton: NSViewRepresentable {
    let state: ControlIslandTabInfoState
    let makeMenu: () -> NSMenu
    let onClose: () -> Void
    var onOpen: () -> Void = {}
    @Environment(\.appearsActive) private var appearsActive

    func makeNSView(context _: Context) -> ControlIslandTabMenuNSButton {
        let button = ControlIslandTabMenuNSButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.addItem(withTitle: "")
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More tab actions")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        button.imagePosition = .imageOnly
        button.focusRingType = .none
        button.setAccessibilityLabel("More tab actions")
        button.toolTip = "More tab actions"
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        button.menu?.autoenablesItems = false
        button.menu?.delegate = button
        return button
    }

    func updateNSView(_ button: ControlIslandTabMenuNSButton, context _: Context) {
        button.makeMenu = makeMenu
        button.infoState = state
        button.onClose = onClose
        button.onOpen = onOpen
        button.contentTintColor = appearsActive ? .labelColor : .secondaryLabelColor
    }

    static func dismantleNSView(_ button: ControlIslandTabMenuNSButton, coordinator _: ()) {
        button.cancelPresentation()
    }
}
