import AppKit
import Foundation
import Observation
import SwiftUI

/// Manages tab preview state for Safari-style hover previews.
///
/// `TabPreviewManager` coordinates the lifecycle of tab hover previews:
/// - Tracks which tab is being hovered and its position in global coordinates
/// - Delays preview display to avoid flicker on quick mouse movements
///
/// ## Architecture
///
/// This manager is instantiated per-window and injected via `RefraxEnvironment`.
/// Position is tracked in global (window) coordinates so the preview can be
/// rendered in the `OverlayContainer` which sits above all split view content.
///
/// The `TabPreviewProvider` is shared with `TabSwitcherManager` and injected
/// at initialization. The preview view is a `ThumbnailAdapter` obtained from
/// the provider via `thumbnailView(for:)`.
///
/// ## Usage
///
/// ```swift
/// // In TabView hover handler (using global coordinates)
/// tabPreviewManager.startHover(tab: tab, globalFrame: tabFrame)
///
/// // When hover ends
/// tabPreviewManager.endHover()
/// ```
@Observable
final class TabPreviewManager {
    // MARK: - Dependencies

    @ObservationIgnored
    unowned let previewProvider: TabPreviewProvider

    @ObservationIgnored
    unowned let settings: BrowserSettings

    // MARK: - Public State

    /// Whether the preview should be visible.
    ///
    /// Becomes `true` after the display delay if still hovering.
    private(set) var isPreviewVisible: Bool = false

    /// The frame of the hovered tab in global (window) coordinates.
    ///
    /// Used by OverlayContainer to position the preview correctly.
    private(set) var hoveredTabFrame: CGRect = .zero

    /// The currently hovered tab, if any.
    @ObservationIgnored
    private(set) var hoveredTab: Tab?

    // MARK: - Private State

    @ObservationIgnored
    private var displayDelayTask: Task<Void, any Error>?

    // MARK: - Constants

    private enum Timing {
        /// Delay before showing preview to avoid flicker on quick mouse movements.
        static let displayDelay: Duration = .milliseconds(300)
    }

    // MARK: - Initialization

    /// Creates a TabPreviewManager with a shared preview provider.
    ///
    /// - Parameter previewProvider: The shared provider for thumbnail views.
    init(previewProvider: TabPreviewProvider, browserSettings: BrowserSettings) {
        self.previewProvider = previewProvider
        self.settings = browserSettings
    }

    isolated deinit {
        displayDelayTask?.cancel()
    }

    // MARK: - Public API

    /// Begins tracking hover on a tab.
    ///
    /// Delays preview display to avoid flicker on quick mouse movements.
    /// The thumbnail is created when the preview becomes visible.
    ///
    /// - Parameters:
    ///   - tab: The tab being hovered.
    ///   - globalFrame: The frame of the tab row in global (window) coordinates.
    func startHover(tab: Tab, globalFrame: CGRect) {
        // Bail early if tab previews are disabled in settings
        guard settings.showTabPreviews else { return }

        guard hoveredTab?.id != tab.id else {
            hoveredTabFrame = globalFrame
            return
        }

        cancelPendingWork()

        hoveredTab = tab
        hoveredTabFrame = globalFrame

        displayDelayTask = Task { [weak self] in
            guard let self else { return }

            try await Task.sleep(for: Timing.displayDelay)
            guard hoveredTab?.id == tab.id else { return }

            isPreviewVisible = true
        }
    }

    /// Updates the hovered tab frame while hovering.
    ///
    /// Call this when the tab list scrolls to keep the preview aligned.
    ///
    /// - Parameter globalFrame: The new frame of the tab row in global coordinates.
    func updateFrame(_ globalFrame: CGRect) {
        hoveredTabFrame = globalFrame
    }

    /// Ends hover tracking and cancels pending work.
    ///
    /// Call this when the mouse leaves the tab.
    func endHover() {
        cancelPendingWork()
        hoveredTab = nil
        hoveredTabFrame = .zero
        isPreviewVisible = false
    }

    /// Ends hover if the tab matches the currently hovered tab.
    ///
    /// Use this variant when you need to check the tab ID before ending.
    ///
    /// - Parameter tab: The tab that lost hover.
    func endHover(for tab: Tab) {
        guard hoveredTab?.id == tab.id else { return }
        endHover()
    }

    // MARK: - Private Helpers

    private func cancelPendingWork() {
        displayDelayTask?.cancel()
        displayDelayTask = nil
    }
}
