import Foundation
import Intents
import Observation
import SwiftData

/// Manages integration with macOS Focus Mode for automatic space switching.
///
/// When a Focus Mode activates, FocusModeManager can automatically switch all
/// browser windows to a mapped space. This creates a seamless productivity
/// environment that responds to the user's system-wide focus state.
///
/// ## Focus Mode Detection
///
/// Uses `INFocusStatusCenter` from the Intents framework to observe Focus
/// Mode changes. The app must request authorization, which is done implicitly
/// on first access.
///
/// ## Limitations
///
/// - Focus Mode names/identifiers aren't directly exposed by Apple
/// - Detection relies on Focus status + distributed notification observation
/// - Some Focus Mode types may not be distinguishable
@Observable
final class FocusModeManager {
    // MARK: - State

    /// Whether any Focus Mode is currently active.
    private(set) var isFocusActive: Bool = false

    /// Display name of the current Focus Mode (if detectable).
    private(set) var currentFocusName: String?

    // MARK: - Dependencies

    private unowned let spaceManager: SpaceManager
    private unowned let windowManager: WindowManager
    private let modelContext: ModelContext

    // MARK: - Initialization

    init(
        spaceManager: SpaceManager,
        windowManager: WindowManager,
        modelContext: ModelContext,
    ) {
        self.spaceManager = spaceManager
        self.windowManager = windowManager
        self.modelContext = modelContext

        setupFocusObservation()
        checkCurrentFocusMode()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Focus Observation

    private func setupFocusObservation() {
        // Request authorization implicitly by accessing focus status
        Task {
            _ = INFocusStatusCenter.default.authorizationStatus
        }

        // Observe Focus Mode changes via Intents notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(focusStatusDidChange),
            name: NSNotification.Name("INFocusStatusDidChangeNotification"),
            object: nil,
        )

        // Also observe distributed notification for Focus Mode name
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(focusStatusDidChange),
            name: NSNotification.Name("com.apple.donotdisturb.stateChanged"),
            object: nil,
        )
    }

    @objc
    private func focusStatusDidChange() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.checkCurrentFocusMode()
            }
        }
    }

    private func checkCurrentFocusMode() {
        let focusStatus = INFocusStatusCenter.default.focusStatus
        let wasActive = isFocusActive
        let previousName = currentFocusName

        isFocusActive = focusStatus.isFocused ?? false

        currentFocusName = isFocusActive ? detectFocusModeName() : nil

        // Only trigger actions if Focus actually changed
        if isFocusActive != wasActive || currentFocusName != previousName {
            handleFocusModeChange()
        }
    }

    /// Attempts to detect the Focus Mode name.
    ///
    /// Apple doesn't expose Focus Mode names directly, so this uses
    /// heuristics and cached values.
    private func detectFocusModeName() -> String? {
        UserDefaults.standard.string(forKey: "FocusMode.lastKnownName")
    }

    // MARK: - Focus Mode Handling

    private func handleFocusModeChange() {
        guard isFocusActive else {
            // Focus disabled - clear restrictions but don't switch spaces back
            Logger.info("Focus Mode disabled", category: Logger.ui)
            RestrictionEnforcer.shared.clearRestrictions()
            return
        }

        guard let focusName = currentFocusName else {
            Logger.info("Focus Mode active but name unknown", category: Logger.ui)
            RestrictionEnforcer.shared.clearRestrictions()
            return
        }

        // Find mapping for this Focus Mode
        guard let mapping = fetchMapping(for: focusName) else {
            Logger.info("No mapping for Focus Mode '\(focusName)'", category: Logger.ui)
            RestrictionEnforcer.shared.clearRestrictions()
            return
        }

        applyFocusModeMapping(mapping)
    }

    private func applyFocusModeMapping(_ mapping: FocusModeMapping) {
        guard mapping.isEnabled else {
            RestrictionEnforcer.shared.clearRestrictions()
            return
        }

        // Update last triggered timestamp
        mapping.lastTriggeredAt = Date()

        // Update restriction enforcer with domain restrictions
        RestrictionEnforcer.shared.updateFocusRestrictions(
            blockedDomains: mapping.restrictedDomains,
            blurredDomains: mapping.blurredDomains,
            suppressNotifications: mapping.suppressNotifications,
            focusIdentifier: mapping.focusIdentifier,
        )

        // Switch all windows to the mapped space
        if let spaceID = mapping.targetSpaceID,
           let space = spaceManager.spaces.first(where: { $0.id == spaceID }) {
            let windowStates = windowManager.allWindowStates

            Logger.info(
                "Focus Mode '\(mapping.focusDisplayName)' → switching \(windowStates.count) windows to '\(space.name)'",
                category: Logger.ui,
            )

            for windowState in windowStates {
                // Use sync version since we're batch-switching
                // and Focus Mode spaces shouldn't be locked
                spaceManager.switchToSpaceSync(space, for: windowState)
            }
        }
    }

    // MARK: - Data Access

    private func fetchMapping(for focusName: String) -> FocusModeMapping? {
        let predicate = #Predicate<FocusModeMapping> { mapping in
            mapping.focusDisplayName == focusName && mapping.isEnabled
        }
        let descriptor = FetchDescriptor<FocusModeMapping>(predicate: predicate)

        do {
            let mappings = try modelContext.fetch(descriptor)
            return mappings.first
        } catch {
            Logger.error("Failed to fetch Focus Mode mapping: \(error)", category: Logger.data)
            return nil
        }
    }

    // MARK: - Public API

    /// All available Focus Mode mappings.
    var mappings: [FocusModeMapping] {
        let descriptor = FetchDescriptor<FocusModeMapping>(
            sortBy: [SortDescriptor(\.focusDisplayName)],
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Creates a new Focus Mode mapping.
    @discardableResult
    func createMapping(focusName: String, targetSpace: Space) -> FocusModeMapping {
        let mapping = FocusModeMapping(focusIdentifier: focusName, focusDisplayName: focusName)
        mapping.targetSpaceID = targetSpace.id

        modelContext.insert(mapping)
        try? modelContext.save()

        Logger.info("Created Focus Mode mapping: '\(focusName)' → '\(targetSpace.name)'", category: Logger.data)
        return mapping
    }

    /// Deletes a Focus Mode mapping.
    func deleteMapping(_ mapping: FocusModeMapping) {
        modelContext.delete(mapping)
        try? modelContext.save()

        Logger.info("Deleted Focus Mode mapping: '\(mapping.focusDisplayName)'", category: Logger.data)
    }
}
