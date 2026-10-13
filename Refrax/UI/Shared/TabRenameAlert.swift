import AppKit

/// Rename… for a tab with no title of its own on screen to edit, such as a row in Recent: a
/// sheet on the window with the name selected.
enum TabRenameAlert {
    private enum Layout {
        static let fieldWidth: CGFloat = 260
        static let fieldHeight: CGFloat = 22
    }

    static func present(for tab: Tab, tabs: TabManager, in window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "Rename Tab"
        alert.informativeText = "Leave the name empty to use the page's title."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: Layout.fieldWidth, height: Layout.fieldHeight))
        field.stringValue = tab.displayTitle
        field.placeholderString = tab.activePage.title
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            TabRenaming.apply(field.stringValue, to: tab, tabs: tabs)
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }
}
