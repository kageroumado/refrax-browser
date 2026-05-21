import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for TabPreviewManager operations.
    @Tag static var tabPreviewManager: Self
}

// MARK: - Test Helper

/// Helper to create TabPreviewManager with required dependencies.
@MainActor
final class TabPreviewTestContext {
    let env: TabManagerTestEnvironment
    let space: Space
    let windowState: WindowState
    let tabManager: TabManager
    let previewProvider: TabPreviewProvider
    let previewManager: TabPreviewManager

    init() throws {
        self.env = try TabManagerTestEnvironment()
        self.space = env.makeSpace()
        self.windowState = env.makeActiveWindowState(with: space)
        self.tabManager = env.tabManager
        self.previewProvider = TabPreviewProvider(
            tabManager: env.tabManager,
            windowState: windowState,
        )
        self.previewManager = TabPreviewManager(
            previewProvider: previewProvider,
            browserSettings: env.settings,
        )
        env.settings.showTabPreviews = true
    }
}

// MARK: - TabPreviewManager Initial State Tests

@Suite("TabPreviewManager Initial State", .tags(.tabPreviewManager), .serialized)
@MainActor
struct TabPreviewInitialStateTests {
    @Test("Initially not visible")
    func initiallyNotVisible() throws {
        let ctx = try TabPreviewTestContext()

        #expect(!ctx.previewManager.isPreviewVisible)
    }

    @Test("Initially has no hovered tab")
    func initiallyNoHoveredTab() throws {
        let ctx = try TabPreviewTestContext()

        #expect(ctx.previewManager.hoveredTab == nil)
    }

    @Test("Initially has zero frame")
    func initiallyZeroFrame() throws {
        let ctx = try TabPreviewTestContext()

        #expect(ctx.previewManager.hoveredTabFrame == .zero)
    }

    @Test("Preview provider exists")
    func previewProviderExists() throws {
        let ctx = try TabPreviewTestContext()

        _ = ctx.previewManager.previewProvider
    }
}

// MARK: - TabPreviewManager Start Hover Tests

@Suite("TabPreviewManager Start Hover", .tags(.tabPreviewManager), .serialized)
@MainActor
struct TabPreviewStartHoverTests {
    @Test("Start hover sets hovered tab")
    func startHoverSetsTab() throws {
        let ctx = try TabPreviewTestContext()

        let tab = ctx.env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: ctx.space,
            makeActive: true,
        )
        let frame = CGRect(x: 100, y: 200, width: 300, height: 50)

        ctx.previewManager.startHover(tab: tab, globalFrame: frame)

        #expect(ctx.previewManager.hoveredTab?.id == tab.id)
        #expect(ctx.previewManager.hoveredTabFrame == frame)
    }

    @Test("Start hover does not immediately show preview")
    func startHoverNotImmediatelyVisible() throws {
        let ctx = try TabPreviewTestContext()

        let tab = ctx.env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: ctx.space,
            makeActive: true,
        )

        ctx.previewManager.startHover(tab: tab, globalFrame: .zero)

        // Preview visibility is delayed
        #expect(!ctx.previewManager.isPreviewVisible)
    }

    @Test("Start hover on same tab updates frame only")
    func startHoverSameTabUpdatesFrame() throws {
        let ctx = try TabPreviewTestContext()

        let tab = ctx.env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: ctx.space,
            makeActive: true,
        )
        let frame1 = CGRect(x: 100, y: 200, width: 300, height: 50)
        let frame2 = CGRect(x: 150, y: 250, width: 300, height: 50)

        ctx.previewManager.startHover(tab: tab, globalFrame: frame1)
        #expect(ctx.previewManager.hoveredTabFrame == frame1)

        ctx.previewManager.startHover(tab: tab, globalFrame: frame2)
        #expect(ctx.previewManager.hoveredTabFrame == frame2)
        #expect(ctx.previewManager.hoveredTab?.id == tab.id)
    }

    @Test("Start hover on different tab resets state")
    func startHoverDifferentTabResets() throws {
        let ctx = try TabPreviewTestContext()

        let tab1 = ctx.env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: ctx.space,
            makeActive: true,
        )
        let tab2 = ctx.env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: ctx.space,
            makeActive: false,
        )

        let frame1 = CGRect(x: 100, y: 200, width: 300, height: 50)
        let frame2 = CGRect(x: 200, y: 300, width: 300, height: 50)

        ctx.previewManager.startHover(tab: tab1, globalFrame: frame1)
        #expect(ctx.previewManager.hoveredTab?.id == tab1.id)

        ctx.previewManager.startHover(tab: tab2, globalFrame: frame2)
        #expect(ctx.previewManager.hoveredTab?.id == tab2.id)
        #expect(ctx.previewManager.hoveredTabFrame == frame2)
    }
}

// MARK: - TabPreviewManager Update Frame Tests

@Suite("TabPreviewManager Update Frame", .tags(.tabPreviewManager), .serialized)
@MainActor
struct TabPreviewUpdateFrameTests {
    @Test("Update frame changes hovered tab frame")
    func updateFrameChangesFrame() throws {
        let ctx = try TabPreviewTestContext()

        let tab = ctx.env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: ctx.space,
            makeActive: true,
        )
        let initialFrame = CGRect(x: 100, y: 200, width: 300, height: 50)
        let updatedFrame = CGRect(x: 100, y: 250, width: 300, height: 50)

        ctx.previewManager.startHover(tab: tab, globalFrame: initialFrame)
        #expect(ctx.previewManager.hoveredTabFrame == initialFrame)

        ctx.previewManager.updateFrame(updatedFrame)
        #expect(ctx.previewManager.hoveredTabFrame == updatedFrame)
    }
}

// MARK: - TabPreviewManager End Hover Tests

@Suite("TabPreviewManager End Hover", .tags(.tabPreviewManager), .serialized)
@MainActor
struct TabPreviewEndHoverTests {
    @Test("End hover clears all state")
    func endHoverClearsState() throws {
        let ctx = try TabPreviewTestContext()

        let tab = ctx.env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: ctx.space,
            makeActive: true,
        )
        let frame = CGRect(x: 100, y: 200, width: 300, height: 50)

        ctx.previewManager.startHover(tab: tab, globalFrame: frame)
        #expect(ctx.previewManager.hoveredTab != nil)

        ctx.previewManager.endHover()

        #expect(ctx.previewManager.hoveredTab == nil)
        #expect(ctx.previewManager.hoveredTabFrame == .zero)
        #expect(!ctx.previewManager.isPreviewVisible)
    }

    @Test("End hover for specific tab only ends if matching")
    func endHoverForTabMatchingOnly() throws {
        let ctx = try TabPreviewTestContext()

        let tab1 = ctx.env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: ctx.space,
            makeActive: true,
        )
        let tab2 = ctx.env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: ctx.space,
            makeActive: false,
        )

        let frame = CGRect(x: 100, y: 200, width: 300, height: 50)

        ctx.previewManager.startHover(tab: tab1, globalFrame: frame)

        // End hover for different tab - should be no-op
        ctx.previewManager.endHover(for: tab2)

        #expect(ctx.previewManager.hoveredTab?.id == tab1.id, "Should still be hovering tab1")

        // End hover for correct tab
        ctx.previewManager.endHover(for: tab1)

        #expect(ctx.previewManager.hoveredTab == nil)
    }

    @Test("End hover is safe when not hovering")
    func endHoverSafeWhenNotHovering() throws {
        let ctx = try TabPreviewTestContext()

        // Should not crash
        ctx.previewManager.endHover()

        #expect(ctx.previewManager.hoveredTab == nil)
        #expect(!ctx.previewManager.isPreviewVisible)
    }

    @Test("End hover for specific tab is safe when not hovering")
    func endHoverForTabSafeWhenNotHovering() throws {
        let ctx = try TabPreviewTestContext()

        let tab = ctx.env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: ctx.space,
            makeActive: true,
        )

        // Should not crash
        ctx.previewManager.endHover(for: tab)

        #expect(ctx.previewManager.hoveredTab == nil)
    }
}

// MARK: - TabPreviewManager Edge Cases

@Suite("TabPreviewManager Edge Cases", .tags(.tabPreviewManager), .serialized)
@MainActor
struct TabPreviewEdgeCaseTests {
    @Test("Works with minimal provider")
    func worksWithMinimalProvider() throws {
        let ctx = try TabPreviewTestContext()

        // Create a manager with a minimal provider (no dependencies)
        let provider = TabPreviewProvider(tabManager: ctx.tabManager, windowState: ctx.windowState)
        let manager = TabPreviewManager(previewProvider: provider, browserSettings: ctx.env.settings)

        let tab = ctx.env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: ctx.space,
            makeActive: true,
        )
        let frame = CGRect(x: 100, y: 200, width: 300, height: 50)

        // Should not crash with minimal provider
        manager.startHover(tab: tab, globalFrame: frame)

        #expect(manager.hoveredTab?.id == tab.id)
        #expect(manager.hoveredTabFrame == frame)
    }

    @Test("Rapid hover changes don't crash")
    func rapidHoverChanges() throws {
        let ctx = try TabPreviewTestContext()

        let tabs = (0 ..< 5).map { i in
            ctx.env.tabManager.createTab(
                url: URL(string: "https://tab\(i).com")!,
                in: ctx.space,
                makeActive: false,
            )
        }

        // Rapidly hover over different tabs
        for tab in tabs {
            let frame = CGRect(
                x: Double.random(in: 0 ... 500),
                y: Double.random(in: 0 ... 500),
                width: 300,
                height: 50,
            )
            ctx.previewManager.startHover(tab: tab, globalFrame: frame)
        }

        // End hover
        ctx.previewManager.endHover()

        #expect(ctx.previewManager.hoveredTab == nil)
    }
}
