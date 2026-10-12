import AppKit

final class ControlIslandTabMenuNSButton: NSPopUpButton, NSMenuDelegate {
    var makeMenu: () -> NSMenu = { NSMenu() }
    var onClose: () -> Void = {}
    var onOpen: () -> Void = {}
    weak var infoState: ControlIslandTabInfoState?
    func menuNeedsUpdate(_ menu: NSMenu) {
        let icon = image
        menu.removeAllItems()
        let titleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        titleItem.image = icon
        menu.addItem(titleItem)
        let actions = makeMenu()
        for item in actions.items {
            actions.removeItem(item)
            menu.addItem(item)
        }
    }

    func cancelPresentation() {
        menu?.cancelTracking()
        infoState?.isMenuPresented = false
    }

    func menuWillOpen(_: NSMenu) {
        infoState?.isMenuPresented = true
        onOpen()
    }

    func menuDidClose(_: NSMenu) {
        infoState?.isHovered = false
        infoState?.isMenuPresented = false
        onClose()
    }
}
