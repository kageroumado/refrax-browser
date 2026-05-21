import Foundation
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for HistoryActivityManager operations.
    @Tag static var historyActivityManager: Self
}

// MARK: - Page Registration Tests

@Suite("HistoryActivityManager Registration", .tags(.historyActivityManager), .serialized)
@MainActor
struct HistoryActivityManagerRegistrationTests {
    /// Creates a manager with app active state for testing.
    private func makeActiveManager() -> HistoryActivityManager {
        let manager = HistoryActivityManager()
        manager.setAppActiveForTesting(true)
        return manager
    }

    @Test("Registered page in key window is active")
    func registeredPageInKeyWindowIsActive() {
        let manager = makeActiveManager()
        let pageID = UUID()
        let windowID = ObjectIdentifier(NSObject())

        manager.registerPage(pageID, windowID: windowID)
        manager.updateWindowKey(windowID: windowID, isKey: true)

        #expect(manager.isPageActive(pageID))
    }

    @Test("Registered page in non-key window is not active")
    func registeredPageInNonKeyWindowIsNotActive() {
        let manager = makeActiveManager()
        let pageID = UUID()
        let windowID = ObjectIdentifier(NSObject())

        manager.registerPage(pageID, windowID: windowID)
        // Window not marked as key

        #expect(!manager.isPageActive(pageID))
    }

    @Test("Unregistered page is not active")
    func unregisteredPageIsNotActive() {
        let manager = makeActiveManager()
        let pageID = UUID()
        let windowID = ObjectIdentifier(NSObject())

        manager.registerPage(pageID, windowID: windowID)
        manager.updateWindowKey(windowID: windowID, isKey: true)
        manager.unregisterPage(pageID, windowID: windowID)

        #expect(!manager.isPageActive(pageID))
    }

    @Test("Registering page triggers callback if now active")
    func registerPageTriggersCallback() async {
        let manager = makeActiveManager()
        let pageID = UUID()
        let windowID = ObjectIdentifier(NSObject())

        var callbackPageID: UUID?
        var callbackIsActive: Bool?
        manager.onPageActivityChanged = { id, isActive in
            callbackPageID = id
            callbackIsActive = isActive
        }

        // First set window as key (before registration, no callback expected)
        manager.updateWindowKey(windowID: windowID, isKey: true)

        // Then register the page (should trigger callback since window is key)
        manager.registerPage(pageID, windowID: windowID)

        #expect(callbackPageID == pageID)
        #expect(callbackIsActive == true)
    }

    @Test("Unregistering page triggers callback if was active")
    func unregisterPageTriggersCallback() {
        let manager = makeActiveManager()
        let pageID = UUID()
        let windowID = ObjectIdentifier(NSObject())

        manager.registerPage(pageID, windowID: windowID)
        manager.updateWindowKey(windowID: windowID, isKey: true)

        var callbackPageID: UUID?
        var callbackIsActive: Bool?
        manager.onPageActivityChanged = { id, isActive in
            callbackPageID = id
            callbackIsActive = isActive
        }

        manager.unregisterPage(pageID, windowID: windowID)

        #expect(callbackPageID == pageID)
        #expect(callbackIsActive == false)
    }
}

// MARK: - Window Key State Tests

@Suite("HistoryActivityManager Window Key", .tags(.historyActivityManager), .serialized)
@MainActor
struct HistoryActivityManagerWindowKeyTests {
    /// Creates a manager with app active state for testing.
    private func makeActiveManager() -> HistoryActivityManager {
        let manager = HistoryActivityManager()
        manager.setAppActiveForTesting(true)
        return manager
    }

    @Test("Window becoming key activates its pages")
    func windowBecomingKeyActivatesPages() {
        let manager = makeActiveManager()
        let pageID = UUID()
        let windowID = ObjectIdentifier(NSObject())

        manager.registerPage(pageID, windowID: windowID)

        var callbackIsActive: Bool?
        manager.onPageActivityChanged = { _, isActive in
            callbackIsActive = isActive
        }

        manager.updateWindowKey(windowID: windowID, isKey: true)

        #expect(manager.isPageActive(pageID))
        #expect(callbackIsActive == true)
    }

    @Test("Window resigning key deactivates its pages")
    func windowResigningKeyDeactivatesPages() {
        let manager = makeActiveManager()
        let pageID = UUID()
        let windowID = ObjectIdentifier(NSObject())

        manager.registerPage(pageID, windowID: windowID)
        manager.updateWindowKey(windowID: windowID, isKey: true)

        var callbackIsActive: Bool?
        manager.onPageActivityChanged = { _, isActive in
            callbackIsActive = isActive
        }

        manager.updateWindowKey(windowID: windowID, isKey: false)

        #expect(!manager.isPageActive(pageID))
        #expect(callbackIsActive == false)
    }

    @Test("Pages in different windows have independent key state")
    func pagesInDifferentWindowsIndependentKeyState() {
        let manager = makeActiveManager()
        let pageID1 = UUID()
        let pageID2 = UUID()
        // Keep references to prevent memory reuse
        let window1 = NSObject()
        let window2 = NSObject()
        let windowID1 = ObjectIdentifier(window1)
        let windowID2 = ObjectIdentifier(window2)

        manager.registerPage(pageID1, windowID: windowID1)
        manager.registerPage(pageID2, windowID: windowID2)
        manager.updateWindowKey(windowID: windowID1, isKey: true)

        #expect(manager.isPageActive(pageID1))
        #expect(!manager.isPageActive(pageID2))

        // Keep objects alive until end of test
        _ = (window1, window2)
    }
}

// MARK: - App Active State Tests

@Suite("HistoryActivityManager App State", .tags(.historyActivityManager), .serialized)
@MainActor
struct HistoryActivityManagerAppStateTests {
    @Test("Page not active when app is inactive")
    func pageNotActiveWhenAppInactive() {
        let manager = HistoryActivityManager()
        manager.setAppActiveForTesting(true)
        let pageID = UUID()
        let windowID = ObjectIdentifier(NSObject())

        manager.registerPage(pageID, windowID: windowID)
        manager.updateWindowKey(windowID: windowID, isKey: true)

        // Simulate app becoming inactive
        manager.setAppActiveForTesting(false)

        #expect(!manager.isPageActive(pageID))
    }

    @Test("canTrackTime is false when app is inactive")
    func canTrackTimeWhenAppInactive() {
        let manager = HistoryActivityManager()
        manager.setAppActiveForTesting(false)

        #expect(!manager.canTrackTime)
    }

    @Test("canTrackTime is false when system is sleeping")
    func canTrackTimeWhenSystemSleeping() {
        let manager = HistoryActivityManager()
        manager.setAppActiveForTesting(true)
        manager.setSystemSleepingForTesting(true)

        #expect(!manager.canTrackTime)
    }

    @Test("canTrackTime is true when app is active and not sleeping")
    func canTrackTimeWhenActiveAndAwake() {
        let manager = HistoryActivityManager()
        manager.setAppActiveForTesting(true)
        manager.setSystemSleepingForTesting(false)

        #expect(manager.canTrackTime)
    }

    @Test("App becoming inactive triggers callback for active pages")
    func appBecomingInactiveTriggersCallback() {
        let manager = HistoryActivityManager()
        manager.setAppActiveForTesting(true)
        let pageID = UUID()
        let windowID = ObjectIdentifier(NSObject())

        manager.registerPage(pageID, windowID: windowID)
        manager.updateWindowKey(windowID: windowID, isKey: true)

        var callbackIsActive: Bool?
        manager.onPageActivityChanged = { _, isActive in
            callbackIsActive = isActive
        }

        manager.setAppActiveForTesting(false)

        #expect(callbackIsActive == false)
    }
}

// MARK: - Multiple Pages Tests

@Suite("HistoryActivityManager Multiple Pages", .tags(.historyActivityManager), .serialized)
@MainActor
struct HistoryActivityManagerMultiplePagesTests {
    /// Creates a manager with app active state for testing.
    private func makeActiveManager() -> HistoryActivityManager {
        let manager = HistoryActivityManager()
        manager.setAppActiveForTesting(true)
        return manager
    }

    @Test("Multiple pages in same window share key state")
    func multiplePagesShareKeyState() {
        let manager = makeActiveManager()
        let pageID1 = UUID()
        let pageID2 = UUID()
        let windowID = ObjectIdentifier(NSObject())

        manager.registerPage(pageID1, windowID: windowID)
        manager.registerPage(pageID2, windowID: windowID)
        manager.updateWindowKey(windowID: windowID, isKey: true)

        #expect(manager.isPageActive(pageID1))
        #expect(manager.isPageActive(pageID2))
    }

    @Test("Callback fires for all affected pages when window key changes")
    func callbackFiresForAllAffectedPages() {
        let manager = makeActiveManager()
        let pageID1 = UUID()
        let pageID2 = UUID()
        let windowID = ObjectIdentifier(NSObject())

        manager.registerPage(pageID1, windowID: windowID)
        manager.registerPage(pageID2, windowID: windowID)

        var callbackCount = 0
        manager.onPageActivityChanged = { _, _ in
            callbackCount += 1
        }

        manager.updateWindowKey(windowID: windowID, isKey: true)

        #expect(callbackCount == 2)
    }
}

// MARK: - Multi-Window Tests

@Suite("HistoryActivityManager Multi-Window", .tags(.historyActivityManager), .serialized)
@MainActor
struct HistoryActivityManagerMultiWindowTests {
    /// Creates a manager with app active state for testing.
    private func makeActiveManager() -> HistoryActivityManager {
        let manager = HistoryActivityManager()
        manager.setAppActiveForTesting(true)
        return manager
    }

    @Test("Same page in multiple windows: active if any window is key")
    func samePageInMultipleWindowsActiveIfAnyKey() {
        let manager = makeActiveManager()
        let pageID = UUID()
        // Keep references to prevent memory reuse
        let window1 = NSObject()
        let window2 = NSObject()
        let windowID1 = ObjectIdentifier(window1)
        let windowID2 = ObjectIdentifier(window2)

        // Register same page in both windows
        manager.registerPage(pageID, windowID: windowID1)
        manager.registerPage(pageID, windowID: windowID2)

        // Neither window is key yet
        #expect(!manager.isPageActive(pageID))

        // Make window1 key
        manager.updateWindowKey(windowID: windowID1, isKey: true)
        #expect(manager.isPageActive(pageID))

        // Make window2 key instead (window1 resigns)
        manager.updateWindowKey(windowID: windowID1, isKey: false)
        manager.updateWindowKey(windowID: windowID2, isKey: true)
        #expect(manager.isPageActive(pageID))

        // Keep objects alive until end of test
        _ = (window1, window2)
    }

    @Test("Same page in multiple windows: unregister one window keeps tracking")
    func samePageUnregisterOneWindowKeepsTracking() {
        let manager = makeActiveManager()
        let pageID = UUID()
        // Keep references to prevent memory reuse
        let window1 = NSObject()
        let window2 = NSObject()
        let windowID1 = ObjectIdentifier(window1)
        let windowID2 = ObjectIdentifier(window2)

        // Register same page in both windows
        manager.registerPage(pageID, windowID: windowID1)
        manager.registerPage(pageID, windowID: windowID2)
        manager.updateWindowKey(windowID: windowID1, isKey: true)

        #expect(manager.isPageActive(pageID))

        // Unregister from window1 (the key window)
        manager.unregisterPage(pageID, windowID: windowID1)

        // Page should still be tracked (but inactive since window2 isn't key)
        #expect(!manager.isPageActive(pageID))

        // Make window2 key - page should become active
        manager.updateWindowKey(windowID: windowID2, isKey: true)
        #expect(manager.isPageActive(pageID))

        // Keep objects alive until end of test
        _ = (window1, window2)
    }

    @Test("Same page in multiple windows: unregister all windows stops tracking")
    func samePageUnregisterAllWindowsStopsTracking() {
        let manager = makeActiveManager()
        let pageID = UUID()
        // Keep references to prevent memory reuse
        let window1 = NSObject()
        let window2 = NSObject()
        let windowID1 = ObjectIdentifier(window1)
        let windowID2 = ObjectIdentifier(window2)

        // Register same page in both windows
        manager.registerPage(pageID, windowID: windowID1)
        manager.registerPage(pageID, windowID: windowID2)
        manager.updateWindowKey(windowID: windowID1, isKey: true)
        manager.updateWindowKey(windowID: windowID2, isKey: true)

        #expect(manager.isPageActive(pageID))

        // Unregister from both windows
        manager.unregisterPage(pageID, windowID: windowID1)
        manager.unregisterPage(pageID, windowID: windowID2)

        // Page should no longer be tracked
        #expect(!manager.isPageActive(pageID))

        // Keep objects alive until end of test
        _ = (window1, window2)
    }

    @Test("Same page in multiple windows: callback only fires on state change")
    func samePageCallbackOnlyOnStateChange() {
        let manager = makeActiveManager()
        let pageID = UUID()
        // Keep references to prevent memory reuse
        let window1 = NSObject()
        let window2 = NSObject()
        let windowID1 = ObjectIdentifier(window1)
        let windowID2 = ObjectIdentifier(window2)

        // Register same page in both windows
        manager.registerPage(pageID, windowID: windowID1)
        manager.registerPage(pageID, windowID: windowID2)
        manager.updateWindowKey(windowID: windowID1, isKey: true)

        var callbackCount = 0
        manager.onPageActivityChanged = { _, _ in
            callbackCount += 1
        }

        // Closing one window (unregister) while page is still visible in key window
        // should not trigger callback since page is still active
        manager.unregisterPage(pageID, windowID: windowID2)
        #expect(callbackCount == 0)
        #expect(manager.isPageActive(pageID))

        // Closing the key window should trigger callback
        manager.unregisterPage(pageID, windowID: windowID1)
        #expect(callbackCount == 1)
        #expect(!manager.isPageActive(pageID))

        // Keep objects alive until end of test
        _ = (window1, window2)
    }

    @Test("Window key state change with page in multiple windows")
    func windowKeyChangeWithPageInMultipleWindows() {
        let manager = makeActiveManager()
        let pageID = UUID()
        // Keep references to prevent memory reuse
        let window1 = NSObject()
        let window2 = NSObject()
        let windowID1 = ObjectIdentifier(window1)
        let windowID2 = ObjectIdentifier(window2)

        // Register same page in both windows
        manager.registerPage(pageID, windowID: windowID1)
        manager.registerPage(pageID, windowID: windowID2)

        var callbackCount = 0
        var lastIsActive: Bool?
        manager.onPageActivityChanged = { _, isActive in
            callbackCount += 1
            lastIsActive = isActive
        }

        // Make window1 key - page becomes active
        manager.updateWindowKey(windowID: windowID1, isKey: true)
        #expect(callbackCount == 1)
        #expect(lastIsActive == true)

        // Resign window1 - page becomes inactive (window2 not key)
        manager.updateWindowKey(windowID: windowID1, isKey: false)
        #expect(callbackCount == 2)
        #expect(lastIsActive == false)

        // Make window2 key - page becomes active again
        manager.updateWindowKey(windowID: windowID2, isKey: true)
        #expect(callbackCount == 3)
        #expect(lastIsActive == true)

        // Keep objects alive until end of test
        _ = (window1, window2)
    }
}
