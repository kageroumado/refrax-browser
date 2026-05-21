import Foundation
import SwiftUI

/// Versioned API for external agent access to browser functionality.
///
/// `RefraxAPI` is the primary interface for MCP agents to interact with Refrax.
/// It provides a stable, versioned facade over internal managers with proper
/// permission checking and error handling.
///
/// ## Architecture
///
/// ```
/// ┌─────────────────────────────────────────────────────┐
/// │ MCP Server (external process)                       │
/// └─────────────────────────────────────────────────────┘
///                       │
///                       │ IPC (JSON-RPC)
///                       ▼
/// ┌─────────────────────────────────────────────────────┐
/// │ RefraxAPI                                           │
/// │   - Version management                              │
/// │   - Permission checking                             │
/// │   - Command/Query execution                         │
/// │   - Event streaming                                 │
/// └─────────────────────────────────────────────────────┘
///                       │
///                       │ @MainActor
///                       ▼
/// ┌─────────────────────────────────────────────────────┐
/// │ Internal Managers                                   │
/// │   - TabManager, SpaceManager, etc.                 │
/// └─────────────────────────────────────────────────────┘
/// ```
///
/// ## Usage
///
/// ```swift
/// let api = RefraxAPI(tabManager: tabManager, ...)
///
/// // Set up permissions
/// var permissions = AgentPermissions()
/// permissions.grant([.tabsRead, .tabsWrite])
///
/// // Execute commands
/// let result = try await api.execute(.openTab(url: url, spaceID: nil, activate: true, groupID: nil),
///                                    permissions: permissions)
///
/// // Execute queries
/// let tabs = try await api.execute(.tabs(spaceID: nil), permissions: permissions)
///
/// // Subscribe to events
/// for await event in api.events(matching: .allTabEvents, permissions: permissions) {
///     print("Event: \(event)")
/// }
/// ```
@MainActor
public final class RefraxAPI {
    // MARK: - Version

    /// Current API version for external agents.
    public static let version = "v1"

    // MARK: - Dependencies

    private let tabManager: TabManager
    private let spaceManager: SpaceManager
    private let groupManager: TabGroupManager
    private let historyManager: HistoryManager
    private let pagePool: WebPagePool
    private let state: BrowserState
    private let windowManager: WindowManager

    // MARK: - Initialization

    /// Creates a new RefraxAPI instance.
    ///
    /// All managers are MainActor-isolated.
    init(
        tabManager: TabManager,
        spaceManager: SpaceManager,
        groupManager: TabGroupManager,
        historyManager: HistoryManager,
        pagePool: WebPagePool,
        state: BrowserState,
        windowManager: WindowManager,
    ) {
        self.tabManager = tabManager
        self.spaceManager = spaceManager
        self.groupManager = groupManager
        self.historyManager = historyManager
        self.pagePool = pagePool
        self.state = state
        self.windowManager = windowManager
    }

    // MARK: - Commands

    /// Executes a command with permission checking.
    ///
    /// - Parameters:
    ///   - command: The command to execute.
    ///   - permissions: Agent's current permissions.
    /// - Returns: The result of the command execution.
    /// - Throws: `RefraxError` if permission check fails or command fails.
    public func execute(_ command: APICommand, permissions: AgentPermissions) async throws -> CommandResult {
        let requirements = command.permissionRequirements
        guard requirements.isSatisfied(by: permissions) else {
            throw RefraxError.permissionsDenied(scopes: requirements.requiredScopes)
        }
        return try executeCommand(command)
    }

    // MARK: - Queries

    /// Executes a query with permission checking.
    ///
    /// - Parameters:
    ///   - query: The query to execute.
    ///   - permissions: Agent's current permissions.
    /// - Returns: The result of the query execution.
    /// - Throws: `RefraxError` if permission check fails or query fails.
    public func execute(_ query: APIQuery, permissions: AgentPermissions) async throws -> QueryResult {
        let requirements = query.permissionRequirements
        if case let .tabContent(tabID, _, _) = query {
            guard let domain = state.tab(for: tabID)?.activePage.url.host else {
                throw RefraxError.tabNotFound(id: tabID)
            }
            guard requirements.isSatisfied(by: permissions, domain: domain) else {
                if permissions.hasScope(.contentRead) {
                    throw RefraxError.domainApprovalRequired(domain: domain)
                } else {
                    throw RefraxError.permissionDenied(scope: .contentRead)
                }
            }
        } else {
            guard requirements.isSatisfied(by: permissions) else {
                throw RefraxError.permissionsDenied(scopes: requirements.requiredScopes)
            }
        }

        return try await executeQuery(query)
    }

    // MARK: - Events

    /// Returns an async stream of events matching the filter.
    ///
    /// - Parameters:
    ///   - filter: Events to include in the stream.
    ///   - permissions: Agent's current permissions.
    /// - Returns: An async stream of matching events.
    ///
    /// - Note: Events are filtered based on the agent's permissions.
    ///   Tab events require `tabsRead`, space events require `spacesRead`, etc.
    public func events(
        matching filter: APIEventFilter,
        permissions: AgentPermissions,
    ) -> AsyncStream<APIEvent> {
        let subscriptionID = UUID()
        let effectiveFilter = effectiveFilter(for: filter, permissions: permissions)

        return AsyncStream { [weak self] continuation in
            self?.registerContinuation(continuation, id: subscriptionID, filter: effectiveFilter)

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.removeContinuation(id: subscriptionID)
                }
            }
        }
    }

    /// Broadcasts an event to all subscribers.
    ///
    /// Called by internal components when state changes occur.
    public func broadcast(_ event: APIEvent) {
        for (_, (continuation, filter)) in eventSubscriptions {
            if event.matches(filter) {
                continuation.yield(event)
            }
        }
    }

    // MARK: - Subscription Management

    /// Active event subscriptions (id -> (continuation, filter)).
    private var eventSubscriptions: [UUID: (AsyncStream<APIEvent>.Continuation, APIEventFilter)] = [:]

    private func registerContinuation(
        _ continuation: AsyncStream<APIEvent>.Continuation,
        id: UUID,
        filter: APIEventFilter,
    ) {
        eventSubscriptions[id] = (continuation, filter)
    }

    private func removeContinuation(id: UUID) {
        eventSubscriptions.removeValue(forKey: id)
    }

    /// Calculates effective filter based on permissions.
    private func effectiveFilter(
        for filter: APIEventFilter,
        permissions: AgentPermissions,
    ) -> APIEventFilter {
        var effective = filter

        // Remove tab events if no tab read permission
        if !permissions.hasScope(.tabsRead) {
            effective.subtract(.allTabEvents)
            effective.subtract(.allNavigationEvents)
        }

        // Remove space events if no space read permission
        if !permissions.hasScope(.spacesRead) {
            effective.subtract(.allSpaceEvents)
        }

        return effective
    }
}

// MARK: - Content Extraction

extension RefraxAPI {
    private func extractPageContent(
        for tab: Tab,
        includeHTML: Bool,
        includeText: Bool,
    ) async throws -> PageContentInfo {
        guard includeHTML || includeText else {
            return PageContentInfo(
                tabID: tab.id,
                pageID: tab.activePage.id,
                url: tab.activePage.url.absoluteString,
                title: tab.displayTitle,
                html: nil,
                textContent: nil,
            )
        }

        guard let webPage = state.webPage(for: tab.activePage.id) else {
            throw RefraxError.invalidState(reason: "Tab page is not loaded")
        }

        let textScript = """
        const root = document.body || document.documentElement;
        return root ? (root.textContent || "") : "";
        """

        let htmlScript = """
        const root = document.documentElement ? document.documentElement.cloneNode(true) : null;
        if (!root) { return ""; }
        root.querySelectorAll("script,style,noscript").forEach(node => node.remove());
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT);
        let node = walker.currentNode;
        while (node) {
            if (node.attributes) {
                const attrs = Array.from(node.attributes);
                for (const attr of attrs) {
                    const name = attr.name.toLowerCase();
                    if (name.startsWith("on")) {
                        node.removeAttribute(attr.name);
                    }
                }
            }
            node = walker.nextNode();
        }
        return root.outerHTML || "";
        """

        let text: String?
        if includeText {
            do {
                text = try await webPage.callJavaScript(textScript) as? String
            } catch {
                throw RefraxError.contentExtractionFailed(reason: error.localizedDescription)
            }
        } else {
            text = nil
        }

        let html: String?
        if includeHTML {
            do {
                html = try await webPage.callJavaScript(htmlScript) as? String
            } catch {
                throw RefraxError.contentExtractionFailed(reason: error.localizedDescription)
            }
        } else {
            html = nil
        }

        return PageContentInfo(
            tabID: tab.id,
            pageID: tab.activePage.id,
            url: tab.activePage.url.absoluteString,
            title: tab.displayTitle,
            html: html,
            textContent: text,
        )
    }
}

// MARK: - Command Execution

extension RefraxAPI {
    private func executeCommand(_ command: APICommand) throws -> CommandResult {
        switch command {
        // MARK: Tab Commands

        case let .openTab(url, spaceID, activate, groupID):
            let space = try resolveSpace(spaceID)
            let tab = tabManager.createTab(
                url: url,
                in: space,
                groupID: groupID,
                makeActive: activate,
            )
            return .tab(TabInfo( tab))

        case let .closeTab(id):
            guard let tab = state.tab(for: id) else { throw RefraxError.tabNotFound(id: id) }
            tabManager.closeTab(tab)
            return .success

        case let .closeTabs(ids):
            let tabs = ids.compactMap { state.tab(for: $0) }
            guard tabs.count == ids.count else {
                let missing = ids.first { state.tab(for: $0) == nil }!
                throw RefraxError.tabNotFound(id: missing)
            }
            tabManager.closeTabs(tabs)
            return .success

        case let .navigate(tabID, url):
            guard let tab = state.tab(for: tabID) else {
                throw RefraxError.tabNotFound(id: tabID)
            }
            guard let page = pagePool.existingPage(for: tab.activePage) else {
                throw RefraxError.invalidState(reason: "Tab has no active page session")
            }
            _ = page.load(url)
            return .success

        case let .reload(tabID, fromOrigin):
            guard let tab = state.tab(for: tabID) else {
                throw RefraxError.tabNotFound(id: tabID)
            }
            guard let page = pagePool.existingPage(for: tab.activePage) else {
                throw RefraxError.invalidState(reason: "Tab has no active page session")
            }
            _ = page.reload(fromOrigin: fromOrigin)
            return .success

        case let .goBack(tabID):
            guard let tab = state.tab(for: tabID) else {
                throw RefraxError.tabNotFound(id: tabID)
            }
            guard let page = pagePool.existingPage(for: tab.activePage) else {
                throw RefraxError.invalidState(reason: "Tab has no active page session")
            }
            page.goBack()
            return .success

        case let .goForward(tabID):
            guard let tab = state.tab(for: tabID) else {
                throw RefraxError.tabNotFound(id: tabID)
            }
            guard let page = pagePool.existingPage(for: tab.activePage) else {
                throw RefraxError.invalidState(reason: "Tab has no active page session")
            }
            page.goForward()
            return .success

        case let .activateTab(id):
            guard let tab = state.tab(for: id) else {
                throw RefraxError.tabNotFound(id: id)
            }
            guard let windowState = windowManager.activeWindowController?.windowState else {
                throw RefraxError.noActiveWindow
            }
            tabManager.setActiveTab(tab, in: windowState)
            return .success

        case let .setTabPinned(id, isPinned):
            guard let tab = state.tab(for: id) else {
                throw RefraxError.tabNotFound(id: id)
            }
            // Only toggle if state change is needed
            if tab.isPinned != isPinned {
                tabManager.togglePinTab(tab)
            }
            return .tab(TabInfo( tab))

        case let .moveTab(id, toIndex):
            guard let tab = state.tab(for: id) else {
                throw RefraxError.tabNotFound(id: id)
            }
            tabManager.moveTab(tab, to: toIndex)
            return .tab(TabInfo( tab))

        case let .moveTabToSpace(id, spaceID):
            guard let tab = state.tab(for: id) else {
                throw RefraxError.tabNotFound(id: id)
            }
            guard let space = state.space(for: spaceID) else {
                throw RefraxError.spaceNotFound(id: spaceID)
            }
            tabManager.moveTabs([tab], to: space)
            return .tab(TabInfo( tab))

        case let .duplicateTab(id, activate):
            guard let tab = state.tab(for: id) else { throw RefraxError.tabNotFound(id: id) }
            let duplicate = tabManager.duplicateTab(tab)
            if activate, let windowState = windowManager.activeWindowController?.windowState {
                tabManager.setActiveTab(duplicate, in: windowState)
            }
            return .tab(TabInfo( duplicate))

        // MARK: Space Commands

        case let .createSpace(name, colorHex, iconName, dataStoreModeString):
            let color = colorHex.map { Color.resolveStoredColor($0) } ?? .steel
            let icon = iconName ?? "globe"
            let mode = dataStoreModeString.flatMap { DataStoreMode(rawValue: $0) } ?? .global
            let space = spaceManager.createSpace(
                name: name,
                color: color,
                iconName: icon,
                dataStoreMode: mode,
            )
            return .space(SpaceInfo( space))

        case let .deleteSpace(id, closeTabs):
            guard let space = state.space(for: id) else {
                throw RefraxError.spaceNotFound(id: id)
            }
            let windowState = windowManager.activeWindowController?.windowState
            spaceManager.deleteSpace(space, closeTabs: closeTabs, windowState: windowState)
            return .success

        case let .updateSpace(id, name, colorHex, iconName):
            guard let space = state.space(for: id) else {
                throw RefraxError.spaceNotFound(id: id)
            }
            let color = colorHex.map { Color.resolveStoredColor($0) }
            spaceManager.updateSpace(space, name: name, iconName: iconName, color: color)
            return .space(SpaceInfo( space))

        case let .switchToSpace(id):
            guard let space = state.space(for: id) else {
                throw RefraxError.spaceNotFound(id: id)
            }
            guard let windowState = windowManager.activeWindowController?.windowState else {
                throw RefraxError.noActiveWindow
            }
            // Check if space is locked and not yet unlocked
            if state.spaceLockManager.requiresAuth(for: space) {
                throw RefraxError.spaceLocked(id: id, name: space.name)
            }
            spaceManager.switchToSpaceSync(space, for: windowState)
            return .success

        // MARK: Group Commands

        case let .createGroup(spaceID, name, colorHex, tabIDs):
            guard let space = state.space(for: spaceID) else {
                throw RefraxError.spaceNotFound(id: spaceID)
            }
            let color = colorHex ?? GroupColor.steel.rawValue
            let group = try groupManager.createGroup(in: space, name: name, color: color)
            // Add tabs to group
            for tabID in tabIDs {
                if let tab = state.tab(for: tabID) {
                    groupManager.moveTabToGroup(tab, group: group)
                }
            }
            return .group(TabGroupInfo( group, tabCount: group.tabCount))

        case let .deleteGroup(id, closeTabs):
            guard let group = findGroup(id: id) else {
                throw RefraxError.groupNotFound(id: id)
            }
            groupManager.deleteGroup(group, deleteContainedTabs: closeTabs)
            return .success

        case let .updateGroup(id, name, colorHex, isCollapsed):
            guard let group = findGroup(id: id) else {
                throw RefraxError.groupNotFound(id: id)
            }
            if let name {
                group.name = name
            }
            if let colorHex {
                group.colorString = colorHex
            }
            if let isCollapsed {
                group.isCollapsed = isCollapsed
            }
            return .group(TabGroupInfo( group, tabCount: group.tabCount))

        case let .addTabsToGroup(groupID, tabIDs):
            guard let group = findGroup(id: groupID) else {
                throw RefraxError.groupNotFound(id: groupID)
            }
            for tabID in tabIDs {
                if let tab = state.tab(for: tabID) {
                    groupManager.moveTabToGroup(tab, group: group)
                }
            }
            return .success

        case let .removeTabsFromGroup(tabIDs):
            for tabID in tabIDs {
                if let tab = state.tab(for: tabID) {
                    groupManager.removeTabFromGroup(tab)
                }
            }
            return .success
        }
    }

    private func resolveSpace(_ spaceID: UUID?) throws -> Space {
        if let spaceID {
            guard let space = state.space(for: spaceID) else {
                throw RefraxError.spaceNotFound(id: spaceID)
            }
            return space
        } else {
            guard let windowState = windowManager.activeWindowController?.windowState,
                  let spaceID = windowState.activeSpaceID,
                  let space = state.space(for: spaceID)
            else {
                throw RefraxError.noActiveWindow
            }
            return space
        }
    }

    private func findGroup(id: UUID) -> TabGroup? {
        for space in state.spaces {
            if let group = space.groups.first(where: { $0.id == id }) {
                return group
            }
        }
        return nil
    }
}

// MARK: - Query Execution

extension RefraxAPI {
    private func executeQuery(_ query: APIQuery) async throws -> QueryResult {
        switch query {
        case let .tabs(spaceID):
            if let spaceID {
                guard let space = state.space(for: spaceID) else {
                    throw RefraxError.spaceNotFound(id: spaceID)
                }
                let tabs = space.mainTabs.map { TabInfo( $0) }
                return .tabs(tabs)
            } else {
                var allTabs: [TabInfo] = []
                for space in state.spaces {
                    allTabs.append(contentsOf: space.mainTabs.map { TabInfo( $0) })
                }
                return .tabs(allTabs)
            }

        case let .tab(id):
            guard let tab = state.tab(for: id) else {
                throw RefraxError.tabNotFound(id: id)
            }
            return .tab(TabInfo( tab))

        case .activeTab:
            guard let windowState = windowManager.activeWindowController?.windowState,
                  let spaceID = windowState.activeSpaceID,
                  let tabID = windowState.activeTabID(for: spaceID),
                  let tab = state.tab(for: tabID)
            else {
                throw RefraxError.noActiveTab
            }
            return .tab(TabInfo( tab))

        case let .referenceTabs(spaceID):
            let space = try resolveSpace(spaceID)
            let tabs = space.referenceTabs.map { TabInfo( $0) }
            return .tabs(tabs)

        case let .tabContent(tabID, includeHTML, includeText):
            guard let tab = state.tab(for: tabID) else {
                throw RefraxError.tabNotFound(id: tabID)
            }
            let content = try await extractPageContent(
                for: tab,
                includeHTML: includeHTML,
                includeText: includeText,
            )
            return .content(content)

        case .spaces:
            let spaces = state.spaces.map { SpaceInfo( $0) }
            return .spaces(spaces)

        case let .space(id):
            guard let space = state.space(for: id) else {
                throw RefraxError.spaceNotFound(id: id)
            }
            return .space(SpaceInfo( space))

        case .activeSpace:
            guard let windowState = windowManager.activeWindowController?.windowState,
                  let spaceID = windowState.activeSpaceID,
                  let space = state.space(for: spaceID)
            else {
                throw RefraxError.noActiveWindow
            }
            return .space(SpaceInfo( space))

        case let .groups(spaceID):
            let space = try resolveSpace(spaceID)
            let groups = space.groups.map { TabGroupInfo( $0, tabCount: $0.tabCount) }
            return .groups(groups)

        case let .group(id):
            guard let group = findGroup(id: id) else {
                throw RefraxError.groupNotFound(id: id)
            }
            return .group(TabGroupInfo( group, tabCount: group.tabCount))

        case let .history(range, limit, offset, domain):
            var entries: [HistoryEntryData]

            // Query by date range if specified
            if let range {
                entries = await historyManager.entries(from: range.start, to: range.end)
            } else {
                // Default to last 30 days
                let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                entries = await historyManager.entries(from: thirtyDaysAgo, to: Date())
            }

            // Apply domain filter if specified
            if let domain {
                entries = entries.filter { $0.domain == domain }
            }

            // Apply offset and limit
            if offset > 0 {
                entries = Array(entries.dropFirst(offset))
            }
            if limit > 0, entries.count > limit {
                entries = Array(entries.prefix(limit))
            }

            let infos = entries.map { HistoryEntryInfo( $0) }
            return .history(infos)

        case let .searchHistory(query, limit):
            let entries = await historyManager.search(query: query, limit: limit)
            let infos = entries.map { HistoryEntryInfo( $0) }
            return .history(infos)

        case .browserState:
            var totalTabCount = 0
            for space in state.spaces {
                totalTabCount += space.tabCount
            }

            let activeWindowState = windowManager.activeWindowController?.windowState
            let activeSpaceID = activeWindowState?.activeSpaceID
            let activeTabID = activeSpaceID.flatMap { activeWindowState?.activeTabID(for: $0) }

            let info = BrowserStateInfo(
                totalTabCount: totalTabCount,
                spaceCount: state.spaces.count,
                activeSpaceID: activeSpaceID,
                activeTabID: activeTabID,
                isContentBlockingReady: state.isContentBlockingReady,
                tabListVersion: state.tabListVersion,
                tabContentVersion: state.tabContentVersion,
            )
            return .browserState(info)
        }
    }
}
