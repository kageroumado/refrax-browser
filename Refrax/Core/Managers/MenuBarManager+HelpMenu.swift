import AppKit

// MARK: - Help Menu

extension MenuBarManager {
    func createHelpMenu() -> NSMenuItem {
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")

        let searchItem = NSMenuItem(
            title: "Search",
            action: nil,
            keyEquivalent: "",
        )
        helpMenu.addItem(searchItem)

        helpMenu.addItem(.separator())

        let helpItem = NSMenuItem(
            title: "Refrax Help",
            action: #selector(showHelp(_:)),
            keyEquivalent: "?",
        )
        helpItem.target = self
        helpMenu.addItem(helpItem)

        let tourItem = NSMenuItem(
            title: "Refrax Tour",
            action: #selector(startFloatingTour(_:)),
            keyEquivalent: "",
        )
        tourItem.image = NSImage(systemSymbolName: "graduationcap", accessibilityDescription: nil)
        tourItem.target = self
        helpMenu.addItem(tourItem)

        helpMenu.addItem(.separator())

        let feedbackItem = NSMenuItem(
            title: "Send Feedback…",
            action: #selector(showFeedback(_:)),
            keyEquivalent: "",
        )
        feedbackItem.image = NSImage(systemSymbolName: "envelope", accessibilityDescription: nil)
        feedbackItem.target = self
        helpMenu.addItem(feedbackItem)

        helpMenu.addItem(.separator())

        let acknowledgementsItem = NSMenuItem(
            title: "Acknowledgements",
            action: #selector(showAcknowledgements(_:)),
            keyEquivalent: "",
        )
        acknowledgementsItem.target = self
        helpMenu.addItem(acknowledgementsItem)

        NSApplication.shared.helpMenu = helpMenu

        helpMenuItem.submenu = helpMenu
        return helpMenuItem
    }

    @objc
    func showHelp(_: Any?) {
        // TODO: Implement help
    }

    /// Walks the active window through opening pages, revealing them, and the control panel.
    @objc
    func startFloatingTour(_: Any?) {
        activeWindowController?.environment.floatingTourManager.start()
    }

    @objc
    func showFeedback(_: Any?) {
        NSApp.typedDelegate.feedbackWindowController.showWindow()
    }

    @objc
    func showAcknowledgements(_: Any?) {
        NSApp.typedDelegate.acknowledgementsWindowController.showWindow()
    }
}
