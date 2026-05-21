import AppKit
import Foundation
import Testing

@testable import Refrax

@Suite("Drag Pasteboard", .tags(.sidebarDragCoordinator))
@MainActor
struct DragPasteboardTests {
    // MARK: - DragPasteboardWriter Tests

    @Test("Pasteboard writer provides correct types for tab")
    func pasteboardWriterTypesForTab() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://example.com")
        let item = Sidebar.DragCoordinator.DraggedItem.tab(tab)

        let writer = DragPasteboardWriter(items: [item])
        let types = writer.supportedTypes

        // Should include: internal tab ID, URL, string
        #expect(types.contains(DragPasteboardType.refraxTabID))
        #expect(types.contains(NSPasteboard.PasteboardType.URL))
        #expect(types.contains(NSPasteboard.PasteboardType.string))

        // Should NOT include favorite ID
        #expect(!types.contains(DragPasteboardType.refraxFavoriteID))
    }

    @Test("Pasteboard writer provides correct types for favorite")
    func pasteboardWriterTypesForFavorite() throws {
        let support = try SidebarTestSupport()
        let favorite = support.createFavorite(title: "Test Favorite", url: "https://example.com")

        let item = Sidebar.DragCoordinator.DraggedItem.favorite(favorite)
        let writer = DragPasteboardWriter(items: [item])
        let types = writer.supportedTypes

        // Should include: internal favorite ID, URL, string
        #expect(types.contains(DragPasteboardType.refraxFavoriteID))
        #expect(types.contains(NSPasteboard.PasteboardType.URL))
        #expect(types.contains(NSPasteboard.PasteboardType.string))

        // Should NOT include tab ID
        #expect(!types.contains(DragPasteboardType.refraxTabID))
    }

    @Test("Pasteboard writer creates item with data provider")
    func pasteboardWriterCreatesItem() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://example.com")
        let item = Sidebar.DragCoordinator.DraggedItem.tab(tab)

        let writer = DragPasteboardWriter(items: [item])
        let pasteboardItem = writer.createPasteboardItem()

        // Item should have types registered
        let types = pasteboardItem.types
        #expect(types.contains(DragPasteboardType.refraxTabID))
    }

    // MARK: - Data Provider Tests

    @Test("Pasteboard provides tab ID data")
    func pasteboardProvidesTabIDData() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://example.com")
        let item = Sidebar.DragCoordinator.DraggedItem.tab(tab)

        let writer = DragPasteboardWriter(items: [item])
        let pasteboardItem = writer.createPasteboardItem()

        // Request data for tab ID type
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([pasteboardItem])

        // Read back and verify
        guard let data = pasteboard.data(forType: DragPasteboardType.refraxTabID),
              let string = String(data: data, encoding: .utf8) else {
            Issue.record("Failed to read tab ID data")
            return
        }

        #expect(string == tab.id.uuidString)
    }

    @Test("Pasteboard provides multiple tab IDs for multi-selection")
    func pasteboardProvidesMultipleTabIDs() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://example1.com")
        let tab2 = support.createTab(url: "https://example2.com")
        let items = [
            Sidebar.DragCoordinator.DraggedItem.tab(tab1),
            Sidebar.DragCoordinator.DraggedItem.tab(tab2),
        ]

        let writer = DragPasteboardWriter(items: items)
        let pasteboardItem = writer.createPasteboardItem()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([pasteboardItem])

        guard let data = pasteboard.data(forType: DragPasteboardType.refraxTabID),
              let string = String(data: data, encoding: .utf8) else {
            Issue.record("Failed to read tab ID data")
            return
        }

        let ids = string.split(separator: "\n")
        #expect(ids.count == 2)
        #expect(ids[0] == Substring(tab1.id.uuidString))
        #expect(ids[1] == Substring(tab2.id.uuidString))
    }

    // MARK: - Reading Helper Tests

    @Test("containsRefraxDragData detects tab data")
    func containsRefraxDragDataDetectsTab() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://example.com")
        let item = Sidebar.DragCoordinator.DraggedItem.tab(tab)

        let writer = DragPasteboardWriter(items: [item])
        let pasteboardItem = writer.createPasteboardItem()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([pasteboardItem])

        #expect(DragPasteboardWriter.containsRefraxDragData(pasteboard))
    }

    @Test("extractTabIDs returns correct UUIDs")
    func extractTabIDsReturnsCorrectUUIDs() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://example1.com")
        let tab2 = support.createTab(url: "https://example2.com")
        let items = [
            Sidebar.DragCoordinator.DraggedItem.tab(tab1),
            Sidebar.DragCoordinator.DraggedItem.tab(tab2),
        ]

        let writer = DragPasteboardWriter(items: items)
        let pasteboardItem = writer.createPasteboardItem()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([pasteboardItem])

        let ids = DragPasteboardWriter.extractTabIDs(from: pasteboard)
        #expect(ids.count == 2)
        #expect(ids.contains(tab1.id))
        #expect(ids.contains(tab2.id))
    }

    @Test("Empty pasteboard returns no Refrax data")
    func emptyPasteboardReturnsNoRefraxData() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        #expect(!DragPasteboardWriter.containsRefraxDragData(pasteboard))
        #expect(DragPasteboardWriter.extractTabIDs(from: pasteboard).isEmpty)
        #expect(DragPasteboardWriter.extractFavoriteIDs(from: pasteboard).isEmpty)
    }
}

// MARK: - WeblocFilePromiseProvider Tests

@Suite("Webloc File Promise", .tags(.sidebarDragCoordinator))
@MainActor
struct WeblocFilePromiseTests {
    @Test("Filename sanitizes forward slashes")
    func filenameSanitizesForwardSlashes() {
        let provider = WeblocFilePromiseProvider(
            url: URL(string: "https://example.com")!,
            title: "Test/Title/With/Slashes",
        )

        let filename = provider.filePromiseProvider(provider, fileNameForType: "")
        #expect(filename == "Test-Title-With-Slashes.webloc")
    }

    @Test("Filename sanitizes colons")
    func filenameSanitizesColons() {
        let provider = WeblocFilePromiseProvider(
            url: URL(string: "https://example.com")!,
            title: "Test: Title: With: Colons",
        )

        let filename = provider.filePromiseProvider(provider, fileNameForType: "")
        #expect(filename == "Test- Title- With- Colons.webloc")
    }

    @Test("Filename handles empty title with hostname fallback")
    func filenameHandlesEmptyTitle() {
        let provider = WeblocFilePromiseProvider(
            url: URL(string: "https://example.com/page")!,
            title: "",
        )

        let filename = provider.filePromiseProvider(provider, fileNameForType: "")
        #expect(filename == "example.com.webloc")
    }

    @Test("Filename handles all-period title with hostname fallback")
    func filenameHandlesAllPeriodTitle() {
        let provider = WeblocFilePromiseProvider(
            url: URL(string: "https://example.com")!,
            title: "...",
        )

        let filename = provider.filePromiseProvider(provider, fileNameForType: "")
        #expect(filename == "example.com.webloc")
    }

    @Test("Filename truncates long titles")
    func filenameTruncatesLongTitles() {
        let longTitle = String(repeating: "A", count: 300)
        let provider = WeblocFilePromiseProvider(
            url: URL(string: "https://example.com")!,
            title: longTitle,
        )

        let filename = provider.filePromiseProvider(provider, fileNameForType: "")
        // 250 chars + .webloc = 257 chars
        #expect(filename.count == 257)
        #expect(filename.hasSuffix(".webloc"))
    }

    @Test("File promise writes valid plist")
    func filePromiseWritesValidPlist() async throws {
        let testURL = URL(string: "https://example.com/test-page")!
        let provider = WeblocFilePromiseProvider(url: testURL, title: "Test Page")

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".webloc")

        // Use continuation to wait for async callback
        let writeError: Error? = await withCheckedContinuation { continuation in
            provider.filePromiseProvider(provider, writePromiseTo: tempFile) { error in
                continuation.resume(returning: error)
            }
        }

        #expect(writeError == nil)

        // Verify file contents
        let data = try Data(contentsOf: tempFile)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)

        guard let dict = plist as? [String: Any],
              let urlString = dict["URL"] as? String else {
            Issue.record("Invalid plist structure")
            return
        }

        #expect(urlString == testURL.absoluteString)

        // Cleanup
        try? FileManager.default.removeItem(at: tempFile)
    }

    @Test("Factory creates providers for tabs")
    func factoryCreatesProvidersForTabs() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://example1.com")
        let tab2 = support.createTab(url: "https://example2.com")
        let items = [
            Sidebar.DragCoordinator.DraggedItem.tab(tab1),
            Sidebar.DragCoordinator.DraggedItem.tab(tab2),
        ]

        let providers = WeblocFilePromiseProvider.providers(for: items)
        #expect(providers.count == 2)
    }

    @Test("Factory skips groups")
    func factorySkipsGroups() throws {
        let support = try SidebarTestSupport()
        let group = try support.createGroup(name: "Test Group")
        let items = [Sidebar.DragCoordinator.DraggedItem.group(group)]

        let providers = WeblocFilePromiseProvider.providers(for: items)
        #expect(providers.isEmpty)
    }
}

// MARK: - Ghost State Tests

@Suite("AppKit Bridge Ghost State", .tags(.sidebarDragCoordinator))
@MainActor
struct AppKitBridgeGhostStateTests {
    @Test("captureGhostState returns nil when not dragging")
    func captureGhostStateReturnsNilWhenNotDragging() throws {
        let support = try SidebarTestSupport()
        let ghostState = support.dragCoordinator.captureGhostState()
        #expect(ghostState == nil)
    }

    @Test("captureGhostState captures all required state")
    func captureGhostStateCapturesAllState() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://example.com")
        support.rebuildLayout()

        // Start a drag
        guard let firstItem = support.layoutManager.normalItems.first,
              let tab = firstItem.tab else {
            Issue.record("No tab to drag")
            return
        }

        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: 0),
            startLocation: CGPoint(x: 100, y: 100),
        )

        let ghostState = support.dragCoordinator.captureGhostState()

        #expect(ghostState != nil)
        #expect(ghostState?.originPosition.collection == .normal)
        #expect(ghostState?.originPosition.localIndex == 0)
        #expect(ghostState?.draggedItems.count == 1)
        #expect(ghostState?.overlayMode == .tabRow)
    }

    @Test("restoreFromGhostState restores drag state")
    func restoreFromGhostStateRestoresState() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://example.com")
        support.rebuildLayout()

        guard let firstItem = support.layoutManager.normalItems.first,
              let tab = firstItem.tab else {
            Issue.record("No tab to drag")
            return
        }

        // Start drag and capture ghost state
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: 0),
            startLocation: CGPoint(x: 100, y: 100),
        )

        guard let ghostState = support.dragCoordinator.captureGhostState() else {
            Issue.record("Failed to capture ghost state")
            return
        }

        // Reset and restore
        support.dragCoordinator.reset()
        #expect(!support.dragCoordinator.isDragging)

        support.dragCoordinator.restoreFromGhostState(ghostState)

        #expect(support.dragCoordinator.isDragging)
        #expect(support.dragCoordinator.primaryDraggedItem?.id == tab.id)
        #expect(support.dragCoordinator._originPosition?.collection == .normal)
        #expect(support.dragCoordinator._originPosition?.localIndex == 0)
    }

    @Test("cursorIsOutsideSidebar detects exit")
    func cursorIsOutsideSidebarDetectsExit() throws {
        let support = try SidebarTestSupport()

        // Set up sidebar bounds (0,0 to 200,350)
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 350))

        // Inside sidebar
        #expect(!support.dragCoordinator.cursorIsOutsideSidebar(at: CGPoint(x: 100, y: 200)))

        // Outside sidebar (to the right)
        #expect(support.dragCoordinator.cursorIsOutsideSidebar(at: CGPoint(x: 250, y: 200)))

        // Outside sidebar (above)
        #expect(support.dragCoordinator.cursorIsOutsideSidebar(at: CGPoint(x: 100, y: -20)))

        // Outside sidebar (below)
        #expect(support.dragCoordinator.cursorIsOutsideSidebar(at: CGPoint(x: 100, y: 400)))
    }

    @Test("handoffPhase resets correctly")
    func handoffPhaseResetsCorrectly() throws {
        let support = try SidebarTestSupport()

        // Default is internal
        #expect(support.dragCoordinator.handoffPhase == .internal)

        // Simulate transition
        support.dragCoordinator.handoffPhase = .transitioning
        #expect(support.dragCoordinator.handoffPhase == .transitioning)

        support.dragCoordinator.handoffPhase = .external
        #expect(support.dragCoordinator.handoffPhase == .external)

        // Reset clears to internal
        support.dragCoordinator.reset()
        #expect(support.dragCoordinator.handoffPhase == .internal)
    }
}
