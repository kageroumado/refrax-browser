import Foundation

/// Executes routing actions to navigate URLs to their destinations.
///
/// Works with `RuleEngine` to implement the full routing system.
/// The engine evaluates rules and returns actions; this executor performs them.
///
/// ## Usage
///
/// ```swift
/// let executor = RoutingActionExecutor(
///     tabManager: tabManager,
///     windowManager: windowManager,
///     spaceManager: spaceManager
/// )
///
/// if let action = ruleEngine.matchingAction(for: context) {
///     executor.execute(action, url: url, context: context)
/// }
/// ```
final class RoutingActionExecutor {
    // MARK: - Dependencies

    private unowned let tabManager: TabManager
    private unowned let windowManager: WindowManager
    private unowned let spaceManager: SpaceManager

    // MARK: - Initialization

    /// Creates a routing action executor.
    ///
    /// - Parameters:
    ///   - tabManager: For creating tabs.
    ///   - windowManager: For creating Glimpse windows.
    ///   - spaceManager: For creating spaces and groups.
    init(
        tabManager: TabManager,
        windowManager: WindowManager,
        spaceManager: SpaceManager,
    ) {
        self.tabManager = tabManager
        self.windowManager = windowManager
        self.spaceManager = spaceManager
    }

    // MARK: - Execution

    /// Executes a routing action for a URL.
    ///
    /// - Parameters:
    ///   - action: The action to execute.
    ///   - url: The URL to navigate.
    ///   - context: The navigation context (for template expansion).
    ///   - makeActive: Whether to make the new tab active.
    /// - Returns: `true` if the action was executed, `false` if it should fall back to default behavior.
    @discardableResult
    func execute(
        _ action: RoutingAction,
        url: URL,
        context _: NavigationContext,
        makeActive: Bool = true,
    ) -> Bool {
        switch action {
        case let .openInSpace(spaceID):
            return executeOpenInSpace(spaceID, url: url, makeActive: makeActive)

        case let .openInGroup(spaceID, groupID):
            return executeOpenInGroup(spaceID: spaceID, groupID: groupID, url: url, makeActive: makeActive)

        case let .createSpace(template):
            return executeCreateSpace(template, url: url, makeActive: makeActive)

        case let .createGroup(spaceID, template):
            return executeCreateGroup(spaceID: spaceID, template: template, url: url, makeActive: makeActive)

        case .openInGlimpse:
            windowManager.createGlimpseWindow(url: url)
            return true

        case .openInBackground:
            // Open in current space but don't activate the tab
            guard let space = tabManager.state.spaces.first else { return false }
            tabManager.createTab(
                url: url,
                in: space,
                makeActive: false,
                loadImmediately: true,
            )
            return true

        case .block:
            Logger.info("Blocked navigation to \(url) by routing rule", category: Logger.tabs)
            // Show toast to inform user the navigation was blocked
            windowManager.activeWindowController?.windowState.showToast(
                "Navigation blocked by routing rule",
            )
            return true
        }
    }

    // MARK: - Action Implementations

    private func executeOpenInSpace(_ spaceID: UUID, url: URL, makeActive: Bool) -> Bool {
        guard let space = tabManager.state.spaces.first(where: { $0.id == spaceID }) else {
            Logger.warning("Routing rule target space \(spaceID) not found, falling back to default", category: Logger.tabs)
            return false
        }

        tabManager.createTab(url: url, in: space, makeActive: makeActive, loadImmediately: true)
        return true
    }

    private func executeOpenInGroup(spaceID: UUID, groupID: UUID, url: URL, makeActive: Bool) -> Bool {
        guard let space = tabManager.state.spaces.first(where: { $0.id == spaceID }) else {
            Logger.warning("Routing rule target space \(spaceID) not found, falling back to default", category: Logger.tabs)
            return false
        }

        guard let group = space.groups.first(where: { $0.id == groupID }) else {
            Logger.warning("Routing rule target group \(groupID) not found, opening in space instead", category: Logger.tabs)
            tabManager.createTab(url: url, in: space, makeActive: makeActive, loadImmediately: true)
            return true
        }

        tabManager.createTab(url: url, in: space, groupID: group.id, makeActive: makeActive, loadImmediately: true)
        return true
    }

    private func executeCreateSpace(_ template: RoutingAction.SpaceTemplate, url: URL, makeActive: Bool) -> Bool {
        let name = template.expandedName(for: url)

        // Check if a space with this name already exists
        if let existingSpace = tabManager.state.spaces.first(where: { $0.name == name }) {
            tabManager.createTab(url: url, in: existingSpace, makeActive: makeActive, loadImmediately: true)
            return true
        }

        // Create a new space with template settings
        let iconName = template.iconName ?? "globe"
        let space = spaceManager.createSpace(name: name, iconName: iconName)

        // Apply optional color
        if let colorHex = template.colorHex {
            space.colorHex = colorHex
        }
        // Note: useSeparateDataStore would need integration with data store management

        tabManager.createTab(url: url, in: space, makeActive: makeActive, loadImmediately: true)
        return true
    }

    private func executeCreateGroup(
        spaceID: UUID,
        template: RoutingAction.GroupTemplate,
        url: URL,
        makeActive: Bool,
    ) -> Bool {
        guard let space = tabManager.state.spaces.first(where: { $0.id == spaceID }) else {
            Logger.warning("Routing rule target space \(spaceID) not found for group creation", category: Logger.tabs)
            return false
        }

        let name = template.expandedName(for: url)

        // Check if a group with this name already exists
        if let existingGroup = space.groups.first(where: { $0.name == name }) {
            tabManager.createTab(url: url, in: space, groupID: existingGroup.id, makeActive: makeActive, loadImmediately: true)
            return true
        }

        // Create a new group
        guard let group = try? tabManager.groupManager.createGroup(in: space, name: name) else {
            Logger.warning("Failed to create group \(name) in space \(spaceID)", category: Logger.tabs)
            tabManager.createTab(url: url, in: space, makeActive: makeActive, loadImmediately: true)
            return true
        }

        // Apply template settings
        if let colorHex = template.colorHex {
            group.colorString = colorHex
        }

        tabManager.createTab(url: url, in: space, groupID: group.id, makeActive: makeActive, loadImmediately: true)
        return true
    }
}
