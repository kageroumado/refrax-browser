import AppKit

// MARK: - Window Menu

extension MenuBarManager {
    func createWindowMenu() -> NSMenuItem {
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.delegate = self

        windowMenu.addItem(NSMenuItem(
            title: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m",
        ))

        windowMenu.addItem(NSMenuItem(
            title: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: "",
        ))

        windowMenu.addItem(.separator())

        // MARK: Window Options Group

        let keepOnTopItem = NSMenuItem(
            title: "Keep on Top",
            action: #selector(toggleKeepOnTop(_:)),
            keyEquivalent: "",
        )
        keepOnTopItem.tag = MenuItemTag.keepOnTop.rawValue
        keepOnTopItem.target = self
        windowMenu.addItem(keepOnTopItem)

        let allDesktopsItem = NSMenuItem(
            title: "Show on All Desktops",
            action: #selector(toggleShowOnAllDesktops(_:)),
            keyEquivalent: "",
        )
        allDesktopsItem.tag = MenuItemTag.showOnAllDesktops.rawValue
        allDesktopsItem.target = self
        windowMenu.addItem(allDesktopsItem)

        let lockSizeItem = NSMenuItem(
            title: "Lock Size",
            action: #selector(toggleLockWindowSize(_:)),
            keyEquivalent: "",
        )
        lockSizeItem.tag = MenuItemTag.lockWindowSize.rawValue
        lockSizeItem.target = self
        windowMenu.addItem(lockSizeItem)

        windowMenu.addItem(.separator())

        // MARK: Appearance & Size Group

        windowMenu.addItem(createOpacitySubmenu())
        windowMenu.addItem(createResizeSubmenu())

        windowMenu.addItem(.separator())

        // Reset all custom window options
        let resetItem = NSMenuItem(
            title: "Reset Window Options",
            action: #selector(resetWindowOptions(_:)),
            keyEquivalent: "",
        )
        resetItem.target = self
        windowMenu.addItem(resetItem)

        windowMenu.addItem(.separator())

        windowMenu.addItem(NSMenuItem(
            title: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: "",
        ))

        NSApplication.shared.windowsMenu = windowMenu
        self.windowMenu = windowMenu

        windowMenuItem.submenu = windowMenu
        return windowMenuItem
    }

    private func createResizeSubmenu() -> NSMenuItem {
        let resizeMenuItem = NSMenuItem(title: "Quick Resize", action: nil, keyEquivalent: "")
        let resizeMenu = NSMenu(title: "Quick Resize")

        // 4:3 Aspect Ratio
        let item4_3_1024 = NSMenuItem(
            title: "1024 × 768 (4:3)",
            action: #selector(resizeTo1024x768(_:)),
            keyEquivalent: "",
        )
        item4_3_1024.target = self
        resizeMenu.addItem(item4_3_1024)

        let item4_3_1280 = NSMenuItem(
            title: "1280 × 960 (4:3)",
            action: #selector(resizeTo1280x960(_:)),
            keyEquivalent: "",
        )
        item4_3_1280.target = self
        resizeMenu.addItem(item4_3_1280)

        resizeMenu.addItem(.separator())

        // 16:9 Aspect Ratio
        let item16_9_1280 = NSMenuItem(
            title: "1280 × 720 (16:9)",
            action: #selector(resizeTo1280x720(_:)),
            keyEquivalent: "",
        )
        item16_9_1280.target = self
        resizeMenu.addItem(item16_9_1280)

        let item16_9_1920 = NSMenuItem(
            title: "1920 × 1080 (16:9)",
            action: #selector(resizeTo1920x1080(_:)),
            keyEquivalent: "",
        )
        item16_9_1920.target = self
        resizeMenu.addItem(item16_9_1920)

        resizeMenuItem.submenu = resizeMenu
        return resizeMenuItem
    }

    private func createOpacitySubmenu() -> NSMenuItem {
        let opacityMenuItem = NSMenuItem(title: "Window Opacity", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu(title: "Window Opacity")

        let opacity100 = NSMenuItem(
            title: "100% (Opaque)",
            action: #selector(setOpacity100(_:)),
            keyEquivalent: "",
        )
        opacity100.tag = MenuItemTag.opacity100.rawValue
        opacity100.target = self
        opacityMenu.addItem(opacity100)

        let opacity80 = NSMenuItem(
            title: "80%",
            action: #selector(setOpacity80(_:)),
            keyEquivalent: "",
        )
        opacity80.tag = MenuItemTag.opacity80.rawValue
        opacity80.target = self
        opacityMenu.addItem(opacity80)

        let opacity60 = NSMenuItem(
            title: "60%",
            action: #selector(setOpacity60(_:)),
            keyEquivalent: "",
        )
        opacity60.tag = MenuItemTag.opacity60.rawValue
        opacity60.target = self
        opacityMenu.addItem(opacity60)

        let opacity40 = NSMenuItem(
            title: "40%",
            action: #selector(setOpacity40(_:)),
            keyEquivalent: "",
        )
        opacity40.tag = MenuItemTag.opacity40.rawValue
        opacity40.target = self
        opacityMenu.addItem(opacity40)

        opacityMenuItem.submenu = opacityMenu
        return opacityMenuItem
    }

    // MARK: - Window Option Actions

    @objc
    func toggleKeepOnTop(_: Any?) {
        guard let window = NSApplication.shared.keyWindow else { return }
        window.level = window.level == .floating ? .normal : .floating
    }

    @objc
    func toggleShowOnAllDesktops(_: Any?) {
        guard let window = NSApplication.shared.keyWindow else { return }
        if window.collectionBehavior.contains(.canJoinAllSpaces) {
            window.collectionBehavior.remove(.canJoinAllSpaces)
        } else {
            window.collectionBehavior.insert(.canJoinAllSpaces)
        }
    }

    @objc
    func toggleLockWindowSize(_: Any?) {
        guard let window = NSApplication.shared.keyWindow else { return }
        if window.styleMask.contains(.resizable) {
            window.styleMask.remove(.resizable)
        } else {
            window.styleMask.insert(.resizable)
        }
    }

    @objc
    func resetWindowOptions(_: Any?) {
        guard let window = NSApplication.shared.keyWindow else { return }
        window.level = .normal
        window.collectionBehavior.remove(.canJoinAllSpaces)
        if !window.styleMask.contains(.resizable) {
            window.styleMask.insert(.resizable)
        }
        window.alphaValue = 1.0
    }

    // MARK: - Opacity Actions

    @objc
    func setOpacity100(_: Any?) {
        NSApplication.shared.keyWindow?.alphaValue = 1.0
    }

    @objc
    func setOpacity80(_: Any?) {
        NSApplication.shared.keyWindow?.alphaValue = 0.8
    }

    @objc
    func setOpacity60(_: Any?) {
        NSApplication.shared.keyWindow?.alphaValue = 0.6
    }

    @objc
    func setOpacity40(_: Any?) {
        NSApplication.shared.keyWindow?.alphaValue = 0.4
    }

    // MARK: - Resize Actions

    @objc
    func resizeTo1024x768(_: Any?) {
        resizeKeyWindow(to: NSSize(width: 1_024, height: 768))
    }

    @objc
    func resizeTo1280x960(_: Any?) {
        resizeKeyWindow(to: NSSize(width: 1_280, height: 960))
    }

    @objc
    func resizeTo1280x720(_: Any?) {
        resizeKeyWindow(to: NSSize(width: 1_280, height: 720))
    }

    @objc
    func resizeTo1920x1080(_: Any?) {
        resizeKeyWindow(to: NSSize(width: 1_920, height: 1_080))
    }

    private func resizeKeyWindow(to size: NSSize) {
        guard let window = NSApplication.shared.keyWindow else { return }
        var frame = window.frame
        // Anchor from top-left: adjust origin.y to keep top edge fixed
        frame.origin.y += frame.height - size.height
        frame.size = size
        window.setFrame(frame, display: true, animate: true)
    }

    // MARK: - Window Menu Updates

    func updateWindowMenu(_ menu: NSMenu) {
        guard menu == windowMenu else { return }
        let window = NSApplication.shared.keyWindow

        // Update keep on top checkmark
        if let keepOnTopItem = menu.item(withTag: MenuItemTag.keepOnTop.rawValue) {
            let isOnTop = window?.level == .floating
            keepOnTopItem.state = isOnTop ? .on : .off
        }

        // Update show on all desktops checkmark
        if let allDesktopsItem = menu.item(withTag: MenuItemTag.showOnAllDesktops.rawValue) {
            let isOnAllDesktops = window?.collectionBehavior.contains(.canJoinAllSpaces) ?? false
            allDesktopsItem.state = isOnAllDesktops ? .on : .off
        }

        // Update lock size checkmark
        if let lockSizeItem = menu.item(withTag: MenuItemTag.lockWindowSize.rawValue) {
            let isLocked = !(window?.styleMask.contains(.resizable) ?? true)
            lockSizeItem.state = isLocked ? .on : .off
        }

        // Update opacity checkmarks
        updateOpacityCheckmarks(for: window)
    }

    private func updateOpacityCheckmarks(for window: NSWindow?) {
        guard let opacityMenu = windowMenu?.item(withTitle: "Window Opacity")?.submenu else { return }
        let currentAlpha = window?.alphaValue ?? 1.0

        // Determine which level is closest
        let opacityLevels: [(tag: MenuItemTag, value: CGFloat)] = [
            (.opacity100, 1.0),
            (.opacity80, 0.8),
            (.opacity60, 0.6),
            (.opacity40, 0.4),
        ]

        for (tag, value) in opacityLevels {
            if let item = opacityMenu.item(withTag: tag.rawValue) {
                // Check if within tolerance (for floating point comparison)
                let isSelected = abs(currentAlpha - value) < 0.05
                item.state = isSelected ? .on : .off
            }
        }
    }
}
