import AppKit

// MARK: - Develop Menu

extension MenuBarManager {
    func createDevelopMenu() -> NSMenuItem {
        let developMenuItem = NSMenuItem()
        let developMenu = NSMenu(title: "Develop")
        developMenu.delegate = self
        developMenu.autoenablesItems = false

        // Show Web Inspector (Cmd+Option+I)
        let showInspectorItem = NSMenuItem(
            title: "Show Web Inspector",
            action: #selector(toggleWebInspector(_:)),
            keyEquivalent: "i",
        )
        showInspectorItem.keyEquivalentModifierMask = [.command, .option]
        showInspectorItem.target = self
        showInspectorItem.tag = DevelopMenuItemTag.toggleInspector.rawValue
        developMenu.addItem(showInspectorItem)

        // Show JavaScript Console (Cmd+Option+C)
        let showConsoleItem = NSMenuItem(
            title: "Show JavaScript Console",
            action: #selector(showJavaScriptConsole(_:)),
            keyEquivalent: "c",
        )
        showConsoleItem.keyEquivalentModifierMask = [.command, .option]
        showConsoleItem.target = self
        developMenu.addItem(showConsoleItem)

        // Show Page Source (Cmd+Option+U)
        let showSourceItem = NSMenuItem(
            title: "Show Page Source",
            action: #selector(showPageSource(_:)),
            keyEquivalent: "u",
        )
        showSourceItem.keyEquivalentModifierMask = [.command, .option]
        showSourceItem.target = self
        developMenu.addItem(showSourceItem)

        // Show Page Resources (Cmd+Option+A)
        let showResourcesItem = NSMenuItem(
            title: "Show Page Resources",
            action: #selector(showPageResources(_:)),
            keyEquivalent: "a",
        )
        showResourcesItem.keyEquivalentModifierMask = [.command, .option]
        showResourcesItem.target = self
        developMenu.addItem(showResourcesItem)

        // --- Separator: Profiling Section ---
        developMenu.addItem(.separator())

        // Start Timeline Recording (Cmd+Option+Shift+T)
        let timelineItem = NSMenuItem(
            title: "Start Timeline Recording",
            action: #selector(toggleTimelineRecording(_:)),
            keyEquivalent: "t",
        )
        timelineItem.keyEquivalentModifierMask = [.command, .option, .shift]
        timelineItem.target = self
        timelineItem.tag = DevelopMenuItemTag.timelineRecording.rawValue
        developMenu.addItem(timelineItem)

        // Start Element Selection (Cmd+Shift+C)
        let elementSelectionItem = NSMenuItem(
            title: "Start Element Selection",
            action: #selector(toggleElementSelection(_:)),
            keyEquivalent: "c",
        )
        elementSelectionItem.keyEquivalentModifierMask = [.command, .shift]
        elementSelectionItem.target = self
        elementSelectionItem.tag = DevelopMenuItemTag.elementSelection.rawValue
        developMenu.addItem(elementSelectionItem)

        // --- Separator: Cache Section ---
        developMenu.addItem(.separator())

        // Empty Caches (Cmd+Option+E)
        let emptyCachesItem = NSMenuItem(
            title: "Empty Caches",
            action: #selector(emptyCaches(_:)),
            keyEquivalent: "e",
        )
        emptyCachesItem.keyEquivalentModifierMask = [.command, .option]
        emptyCachesItem.target = self
        developMenu.addItem(emptyCachesItem)

        #if DEBUG
        developMenu.addItem(.separator())

        let generateTabsItem = NSMenuItem(
            title: "Generate 500 Test Tabs",
            action: #selector(generateDebugTabs(_:)),
            keyEquivalent: "",
        )
        generateTabsItem.target = self
        developMenu.addItem(generateTabsItem)
        #endif

        developMenuItem.submenu = developMenu
        return developMenuItem
    }

    @objc
    func toggleWebInspector(_: Any?) {
        guard let webPage = activeWindowController?.windowState.activeWebPage else { return }
        webPage.toggleWebInspector()
    }

    @objc
    func showJavaScriptConsole(_: Any?) {
        guard let webPage = activeWindowController?.windowState.activeWebPage else { return }
        webPage.showJavaScriptConsole()
    }

    @objc
    func showPageSource(_: Any?) {
        guard let webPage = activeWindowController?.windowState.activeWebPage else { return }
        webPage.showPageSource()
    }

    @objc
    func showPageResources(_: Any?) {
        guard let webPage = activeWindowController?.windowState.activeWebPage else { return }
        webPage.showPageResources()
    }

    @objc
    func toggleTimelineRecording(_: Any?) {
        guard let webPage = activeWindowController?.windowState.activeWebPage else { return }
        webPage.toggleTimelineRecording()
    }

    @objc
    func toggleElementSelection(_: Any?) {
        guard let webPage = activeWindowController?.windowState.activeWebPage else { return }
        webPage.toggleElementSelection()
    }

    #if DEBUG
    @objc
    func generateDebugTabs(_: Any?) {
        guard let controller = activeWindowController,
              let space = controller.windowState.activeSpace
        else { return }
        let appDelegate = NSApplication.shared.typedDelegate
        DebugTabGenerator.generate(
            tabManager: appDelegate.tabManager,
            groupManager: appDelegate.groupManager,
            space: space,
        )
    }
    #endif

    @objc
    func emptyCaches(_: Any?) {
        guard let webPage = activeWindowController?.windowState.activeWebPage else { return }
        webPage.emptyCaches()
    }

    func updateDevelopMenuItems(_ menu: NSMenu) {
        guard menu.title == "Develop" else { return }

        guard let controller = activeWindowController else { return }
        let inspectorManager = NSApplication.shared.typedDelegate.webInspectorManager
        let activeWebPage = controller.windowState.activeWebPage

        for item in menu.items {
            item.isEnabled = true

            switch item.tag {
            case DevelopMenuItemTag.toggleInspector.rawValue:
                let isShown = activeWebPage.map { inspectorManager.isInspectorShown(for: $0.tabPage.id) } ?? false
                item.title = isShown ? "Close Web Inspector" : "Show Web Inspector"

            case DevelopMenuItemTag.timelineRecording.rawValue:
                let isProfiling = activeWebPage.map {
                    inspectorManager.isProfilingPage(for: $0.tabPage.id, webView: $0.backingWebView)
                } ?? false
                item.title = isProfiling ? "Stop Timeline Recording" : "Start Timeline Recording"

            case DevelopMenuItemTag.elementSelection.rawValue:
                let isSelecting = activeWebPage.map {
                    inspectorManager.isElementSelectionActive(for: $0.tabPage.id, webView: $0.backingWebView)
                } ?? false
                item.title = isSelecting ? "Stop Element Selection" : "Start Element Selection"

            default:
                break
            }
        }
    }
}

/// Tags for Develop menu items that need dynamic updates.
private enum DevelopMenuItemTag: Int {
    case toggleInspector = 1_001
    case timelineRecording = 1_002
    case elementSelection = 1_003
}
