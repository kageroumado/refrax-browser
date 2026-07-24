import AppKit

// MARK: - App Menu

extension MenuBarManager {
    func createAppMenu() -> NSMenuItem {
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.delegate = self

        // About
        let aboutItem = NSMenuItem(
            title: "About Refrax",
            action: #selector(showAbout(_:)),
            keyEquivalent: "",
        )
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        // Check for Updates
        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: "",
        )
        updateItem.target = self
        updateItem.tag = MenuItemTag.checkForUpdates.rawValue
        appMenu.addItem(updateItem)

        // Send Feedback
        let feedbackItem = NSMenuItem(
            title: "Send Feedback…",
            action: #selector(showFeedback(_:)),
            keyEquivalent: "",
        )
        feedbackItem.image = NSImage(systemSymbolName: "envelope", accessibilityDescription: nil)
        feedbackItem.target = self
        appMenu.addItem(feedbackItem)

        appMenu.addItem(.separator())

        // Preferences
        let preferencesItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openPreferences(_:)),
            keyEquivalent: ",",
        )
        preferencesItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        preferencesItem.target = self
        appMenu.addItem(preferencesItem)

        appMenu.addItem(.separator())

        // Services
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        servicesItem.submenu = servicesMenu
        NSApplication.shared.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)

        appMenu.addItem(.separator())

        // Hide, Hide Others, Show All
        appMenu.addItem(NSMenuItem(
            title: "Hide Refrax",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h",
        ))

        let hideOthersItem = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        appMenu.addItem(NSMenuItem(
            title: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "",
        ))

        appMenu.addItem(.separator())

        // Quit
        appMenu.addItem(NSMenuItem(
            title: "Quit Refrax",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q",
        ))

        appMenuItem.submenu = appMenu
        return appMenuItem
    }

    @objc
    func showAbout(_: Any?) {
        NSApp.typedDelegate.aboutWindowController.showWindow()
    }

    @objc
    func openPreferences(_: Any?) {
        NSApplication.shared.typedDelegate.settingsWindowController.showWindow()
    }

    @objc
    func checkForUpdates(_: Any?) {
        let manager = NSApp.typedDelegate.appUpdateManager
        if case .readyToInstall = manager.phase {
            Task { await manager.restartToUpdate() }
        } else {
            Task { await manager.checkForUpdates(manual: true) }
        }
    }
}
