import AppKit

// MARK: - State Observation

extension RefraxWindowController {
    func observeWindowState() {
        // Observe settings that affect window background color
        let colorSettingsChanges = Observations {
            (
                self.settings.customWindowBackgroundColorHex,
                self.settings.windowBackgroundMixAmount,
                self.settings.windowBackgroundMixMode,
                self.settings.windowBackgroundFillOpacity,
                self.settings.enableSpaceWindowColoring,
                self.settings.enableWebsiteWindowColoring,
                self.settings.websiteColorUseSolidBlend,
            )
        }
        let settingsTask = Task { @MainActor [weak self] in
            for await _ in colorSettingsChanges {
                self?.updateWindowBackground()
            }
        }
        observationTasks.append(settingsTask)

        // Observe the debounced website color for smooth transitions
        let websiteColorChanges = Observations {
            self.windowState.debouncedWebsiteColor
        }
        let websiteColorTask = Task { @MainActor [weak self] in
            for await _ in websiteColorChanges {
                self?.updateWindowBackground()
            }
        }
        observationTasks.append(websiteColorTask)

        // The active tab is part of the window's restorable state
        let activeTabChanges = Observations {
            self.windowState.activeTabID
        }
        let activeTabTask = Task { @MainActor [weak self] in
            for await _ in activeTabChanges {
                self?.window?.invalidateRestorableState()
            }
        }
        observationTasks.append(activeTabTask)
    }

    /// Observes space lock state so the SwiftUI lock overlay follows it.
    ///
    /// We observe `isSpaceLocked` (a boolean) rather than `lockedSpaceRequiringAuth`
    /// (a Space?) to avoid Sendable issues with PersistentModel objects in async
    /// observation contexts.
    func observeSpaceLockState() {
        let lockChanges = Observations {
            self.windowState.isSpaceLocked
        }

        let task = Task { @MainActor [weak self] in
            for await _ in lockChanges {
                // Bump the version counter so the SwiftUI overlay re-renders. This
                // Observations handler fires reliably; the counter bridges that to
                // SwiftUI views that observe WindowState directly.
                self?.windowState.spaceLockVersion &+= 1
            }
        }
        observationTasks.append(task)
    }

    /// Observes the active webpage's effective color for website window coloring.
    ///
    /// This observation tracks changes to the active tab's theme color and
    /// sampled page top color, forwarding them to WindowState for debouncing.
    func observeWebsiteColor() {
        let colorChanges = Observations {
            self.windowState.activeWebPage?.effectiveWindowColor
        }
        let task = Task { @MainActor [weak self] in
            for await _ in colorChanges {
                guard let self else { return }
                let color = windowState.activeWebPage?.effectiveWindowColor
                windowState.updateWebsiteColor(color)
            }
        }
        observationTasks.append(task)

        // Also observe active tab changes to update/clear website color
        let tabChanges = Observations {
            self.windowState.activeTabID
        }
        let tabTask = Task { @MainActor [weak self] in
            for await _ in tabChanges {
                guard let self else { return }
                // Get the new active page's color
                let color = windowState.activeWebPage?.effectiveWindowColor
                windowState.updateWebsiteColor(color)
            }
        }
        observationTasks.append(tabTask)
    }

    func updateWindowBackground() {
        let background = windowState.resolvedBackground
        let (color, source) = (background.color, background.source)

        // Update fill opacity from settings
        backgroundView.updateFillOpacity(settings.windowBackgroundFillOpacity)

        // Determine the blend mode based on color source and settings
        let useSolidMode = source == .website && settings.websiteColorUseSolidBlend

        if useSolidMode {
            // Solid mode: fully opaque color covering the background
            backgroundView.updateTint(color: color.cgColor, compositingFilter: nil)
        } else {
            // Blended mode: semi-transparent with compositing filter
            let tintColor = color.cgColor.copy(alpha: settings.windowBackgroundMixAmount)
            backgroundView.updateTint(color: tintColor, compositingFilter: settings.windowBackgroundMixMode.makeCIFilter())
        }
    }
}
