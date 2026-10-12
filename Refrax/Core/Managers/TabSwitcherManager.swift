import AppKit
import Observation

/// Keeps a per-window history and presents it for pointer or Control-Tab navigation.
@Observable
final class TabSwitcherManager {
    @ObservationIgnored private unowned let tabManager: TabManager
    @ObservationIgnored private unowned let windowState: WindowState
    @ObservationIgnored private unowned let previewProvider: TabPreviewProvider
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var activationTask: Task<Void, Never>?

    private(set) var isActive = false
    private(set) var commitsOnControlRelease = false
    private var recentlyUsedTabIDs: [Tab.ID] = []
    private var presentedTabIDs: [Tab.ID] = []
    private var selectedTabID: Tab.ID?

    private enum Constants {
        static let maxRecentTabs = 5
        static let minimumTabsForSwitcher = 2
    }

    init(tabManager: TabManager, windowState: WindowState, previewProvider: TabPreviewProvider) {
        self.tabManager = tabManager
        self.windowState = windowState
        self.previewProvider = previewProvider
        startObserving()
    }

    isolated deinit {
        observationTask?.cancel()
        activationTask?.cancel()
    }

    /// The order stays fixed throughout a presentation, including across page activations.
    var recentTabs: [Tab] {
        (isActive ? presentedTabIDs : recentlyUsedTabIDs).compactMap { id in
            guard let tab = tabManager.state.tab(for: id), !tab.isArchived else { return nil }
            return tab
        }
    }

    var selectedIndex: Int {
        recentTabs.firstIndex { $0.id == selectedTabID } ?? 0
    }

    var canShowSwitcher: Bool {
        recentTabs.count >= Constants.minimumTabsForSwitcher
    }

    func preview(for tab: Tab) -> ThumbnailAdapter? {
        previewProvider.preview(for: tab.id)
    }

    /// Keyboard invocation selects the previous tab and commits when Control is released.
    func show() {
        present(commitsOnRelease: true)
    }

    /// Pointer invocation stays open until selection, another click on the trigger, or dismissal.
    func toggle() {
        if isActive { cancel() }
        else { present(commitsOnRelease: false) }
    }

    private func present(commitsOnRelease: Bool) {
        guard canShowSwitcher else { return }
        activationTask?.cancel()
        if let id = windowState.activeTabID { recordTabActivation(id) }
        recentlyUsedTabIDs = recentTabs.map(\.id)
        previewProvider.cleanupStaleEntries()
        presentedTabIDs = recentlyUsedTabIDs
        selectedTabID = presentedTabIDs[min(commitsOnRelease ? 1 : 0, presentedTabIDs.count - 1)]
        commitsOnControlRelease = commitsOnRelease
        isActive = true
    }

    func selectNext() { moveSelection(by: 1) }
    func selectPrevious() { moveSelection(by: -1) }

    private func moveSelection(by offset: Int) {
        let tabs = recentTabs
        guard isActive, !tabs.isEmpty else { return }
        commitsOnControlRelease = true
        selectedTabID = tabs[(selectedIndex + offset + tabs.count) % tabs.count].id
    }

    func controlReleased() {
        if commitsOnControlRelease { dismiss() }
    }

    /// Commits the selected identity, preserving the destination's space and page ownership.
    func dismiss() {
        guard isActive, let selectedTabID else { return }
        activate(tabID: selectedTabID)
    }

    func activate(tabID: Tab.ID) {
        guard isActive else { return }
        cancel()
        guard let tab = tabManager.state.tab(for: tabID), !tab.isArchived else { return }
        activationTask = Task.immediate(name: "Activate recent tab") { [weak self] in
            guard let self else { return }
            if let space = tab.space, space.id != windowState.activeSpaceID || windowState.isSpaceLocked {
                await tabManager.spaceManager.switchToSpace(space, for: windowState)
                guard !Task.isCancelled, windowState.activeSpaceID == space.id,
                      !windowState.isSpaceLocked else { return }
            }
            guard !Task.isCancelled, tabManager.state.tab(for: tabID) != nil, !tab.isArchived else { return }
            tabManager.setActiveTab(tab, in: windowState)
            recordTabActivation(tab.id)
        }
    }

    /// Cancels the pending selection and leaves the current page active.
    func cancel() {
        activationTask?.cancel()
        activationTask = nil
        isActive = false
        commitsOnControlRelease = false
        selectedTabID = nil
        presentedTabIDs = []
    }

    private func startObserving() {
        let changes = Observations { [weak windowState] in windowState?.activeTabID }
        observationTask = Task(name: "Track recent tabs") { [weak self] in
            for await activeTabID in changes {
                guard let self, let activeTabID else { continue }
                recordTabActivation(activeTabID)
            }
        }
    }

    private func recordTabActivation(_ tabID: Tab.ID) {
        recentlyUsedTabIDs.removeAll { $0 == tabID }
        recentlyUsedTabIDs.insert(tabID, at: 0)
        if recentlyUsedTabIDs.count > Constants.maxRecentTabs {
            recentlyUsedTabIDs.removeLast(recentlyUsedTabIDs.count - Constants.maxRecentTabs)
        }
    }
}
