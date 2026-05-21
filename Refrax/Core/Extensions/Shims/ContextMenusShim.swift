import AppKit
import Foundation

/// Shim for `browser.contextMenus` API using NSMenu.
///
/// Implements the WebExtensions contextMenus API for adding items to browser
/// context menus. Integrates with Refrax's existing context menu system.
///
/// ## Menu Structure
///
/// Extension menu items are added to:
/// - Page context menus (right-click on page)
/// - Tab context menus (right-click on tab)
/// - Selection context menus (right-click on selected text)
///
/// ## Limitations
///
/// - Radio button groups are supported but rendered as checkmarks
/// - Some context types are not applicable (browser_action, launcher, etc.)
///
/// ## Thread Safety
///
/// All operations are MainActor-isolated since NSMenu requires main thread access.

final class ContextMenusShim: ExtensionShim {
    // MARK: - Types

    /// A registered context menu item.
    struct MenuItem: Identifiable {
        let id: String
        let extensionID: String
        var parentId: String?
        var title: String
        var type: MenuItemType
        var contexts: Set<ContextType>
        var checked: Bool
        var enabled: Bool
        var visible: Bool
        var documentUrlPatterns: [String]?
        var targetUrlPatterns: [String]?

        /// The callback ID for click events.
        var onClickCallbackId: String?
    }

    enum MenuItemType: String {
        case normal
        case checkbox
        case radio
        case separator
    }

    enum ContextType: String, CaseIterable {
        case all
        case page
        case frame
        case selection
        case link
        case editable
        case image
        case video
        case audio
        case tab
    }

    // MARK: - Properties

    /// Registered menu items keyed by "{extensionID}:{menuItemId}".
    private var menuItems: [String: MenuItem] = [:]

    /// Click handlers for menu items.
    private var clickHandlers: [(MenuItem, [String: Any]) -> Void] = []

    // MARK: - ExtensionShim Protocol

    func handle(method: String, args: [String: Any], extensionID: String) async throws -> Any? {
        switch method {
        case "create":
            guard let createProperties = args["createProperties"] as? [String: Any] else {
                throw ShimError.invalidArguments("'createProperties' is required")
            }
            return try create(properties: createProperties, extensionID: extensionID)

        case "update":
            guard let id = args["id"] as? String else {
                throw ShimError.invalidArguments("'id' is required")
            }
            guard let updateProperties = args["updateProperties"] as? [String: Any] else {
                throw ShimError.invalidArguments("'updateProperties' is required")
            }
            try update(id: id, properties: updateProperties, extensionID: extensionID)
            return nil

        case "remove":
            guard let menuItemId = args["menuItemId"] as? String else {
                throw ShimError.invalidArguments("'menuItemId' is required")
            }
            try remove(id: menuItemId, extensionID: extensionID)
            return nil

        case "removeAll":
            removeAll(extensionID: extensionID)
            return nil

        default:
            throw ShimError.unsupportedMethod(method)
        }
    }

    // MARK: - Menu Operations

    /// Creates a context menu item.
    ///
    /// - Parameters:
    ///   - properties: The menu item properties.
    ///   - extensionID: The calling extension's identifier.
    /// - Returns: The created menu item ID.
    private func create(properties: [String: Any], extensionID: String) throws -> String {
        let id = properties["id"] as? String ?? UUID().uuidString
        let key = "\(extensionID):\(id)"

        // Check for duplicate ID
        if menuItems[key] != nil {
            throw ShimError.invalidArguments("Menu item with id '\(id)' already exists")
        }

        // Parse type
        let typeString = properties["type"] as? String ?? "normal"
        let type = MenuItemType(rawValue: typeString) ?? .normal

        // Parse contexts
        var contexts: Set<ContextType> = []
        if let contextStrings = properties["contexts"] as? [String] {
            for str in contextStrings {
                if let context = ContextType(rawValue: str) {
                    contexts.insert(context)
                }
            }
        }
        if contexts.isEmpty {
            contexts = [.page] // Default to page context
        }

        let menuItem = MenuItem(
            id: id,
            extensionID: extensionID,
            parentId: properties["parentId"] as? String,
            title: properties["title"] as? String ?? "",
            type: type,
            contexts: contexts,
            checked: properties["checked"] as? Bool ?? false,
            enabled: properties["enabled"] as? Bool ?? true,
            visible: properties["visible"] as? Bool ?? true,
            documentUrlPatterns: properties["documentUrlPatterns"] as? [String],
            targetUrlPatterns: properties["targetUrlPatterns"] as? [String],
            onClickCallbackId: properties["onclick"] as? String,
        )

        menuItems[key] = menuItem

        Logger.debug(
            "Created context menu item '\(id)' for extension \(extensionID)",
            category: Logger.extensions,
        )

        return id
    }

    /// Updates a context menu item.
    ///
    /// - Parameters:
    ///   - id: The menu item ID.
    ///   - properties: Properties to update.
    ///   - extensionID: The calling extension's identifier.
    private func update(id: String, properties: [String: Any], extensionID: String) throws {
        let key = "\(extensionID):\(id)"

        guard var item = menuItems[key] else {
            throw ShimError.notFound("Menu item '\(id)'")
        }

        // Update mutable properties
        if let title = properties["title"] as? String {
            item.title = title
        }
        if let checked = properties["checked"] as? Bool {
            item.checked = checked
        }
        if let enabled = properties["enabled"] as? Bool {
            item.enabled = enabled
        }
        if let visible = properties["visible"] as? Bool {
            item.visible = visible
        }
        if let parentId = properties["parentId"] as? String {
            item.parentId = parentId
        }

        menuItems[key] = item
    }

    /// Removes a context menu item.
    ///
    /// - Parameters:
    ///   - id: The menu item ID.
    ///   - extensionID: The calling extension's identifier.
    private func remove(id: String, extensionID: String) throws {
        let key = "\(extensionID):\(id)"

        guard menuItems.removeValue(forKey: key) != nil else {
            throw ShimError.notFound("Menu item '\(id)'")
        }

        // Also remove any children
        let prefix = "\(extensionID):"
        let childKeys = menuItems.keys.filter { key in
            guard let item = menuItems[key] else { return false }
            return item.parentId == id && key.hasPrefix(prefix)
        }
        for childKey in childKeys {
            menuItems.removeValue(forKey: childKey)
        }
    }

    /// Removes all context menu items for an extension.
    ///
    /// - Parameter extensionID: The calling extension's identifier.
    private func removeAll(extensionID: String) {
        let prefix = "\(extensionID):"
        menuItems = menuItems.filter { !$0.key.hasPrefix(prefix) }
    }

    // MARK: - Menu Building

    /// Returns menu items for a specific context and extension.
    ///
    /// - Parameters:
    ///   - context: The context type.
    ///   - extensionID: The extension's identifier.
    ///   - url: The current page URL (for pattern matching).
    /// - Returns: Array of menu items for this context.
    func menuItems(for context: ContextType, extensionID: String, url: URL?) -> [MenuItem] {
        menuItems.values.filter { item in
            // Check extension
            guard item.extensionID == extensionID else { return false }

            // Check visibility
            guard item.visible else { return false }

            // Check context
            guard item.contexts.contains(.all) || item.contexts.contains(context) else {
                return false
            }

            // Check URL patterns if specified
            if let patterns = item.documentUrlPatterns, let url {
                let urlString = url.absoluteString
                let matches = patterns.contains { pattern in
                    matchesPattern(urlString, pattern: pattern)
                }
                if !matches { return false }
            }

            return true
        }.filter { $0.parentId == nil } // Only return top-level items
    }

    /// Returns all menu items for all extensions for a context.
    ///
    /// - Parameters:
    ///   - context: The context type.
    ///   - url: The current page URL.
    /// - Returns: Dictionary mapping extension IDs to their menu items.
    func allMenuItems(for context: ContextType, url: URL?) -> [String: [MenuItem]] {
        var result: [String: [MenuItem]] = [:]

        let extensionIDs = Set(menuItems.values.map(\.extensionID))
        for extensionID in extensionIDs {
            let items = menuItems(for: context, extensionID: extensionID, url: url)
            if !items.isEmpty {
                result[extensionID] = items
            }
        }

        return result
    }

    /// Returns child menu items for a parent.
    ///
    /// - Parameters:
    ///   - parentId: The parent menu item ID.
    ///   - extensionID: The extension's identifier.
    /// - Returns: Array of child menu items.
    func childItems(of parentId: String, extensionID: String) -> [MenuItem] {
        menuItems.values.filter { item in
            item.extensionID == extensionID && item.parentId == parentId && item.visible
        }
    }

    // MARK: - Click Handling

    /// Registers a click handler for menu items.
    ///
    /// - Parameter handler: Called with (MenuItem, clickInfo) when a menu item is clicked.
    func onMenuItemClicked(_ handler: @escaping (MenuItem, [String: Any]) -> Void) {
        clickHandlers.append(handler)
    }

    /// Handles a menu item click.
    ///
    /// - Parameters:
    ///   - item: The clicked menu item.
    ///   - info: Click info (selectionText, pageUrl, etc.).
    func handleClick(_ item: MenuItem, info: [String: Any]) {
        // Toggle checkbox state
        if item.type == .checkbox {
            let key = "\(item.extensionID):\(item.id)"
            menuItems[key]?.checked.toggle()
        }

        // Notify handlers
        for handler in clickHandlers {
            handler(item, info)
        }
    }

    // MARK: - Pattern Matching

    /// Simple glob-style pattern matching for URL patterns.
    private func matchesPattern(_ url: String, pattern: String) -> Bool {
        // Handle <all_urls>
        if pattern == "<all_urls>" {
            return true
        }

        // Convert glob pattern to regex
        var regexPattern = NSRegularExpression.escapedPattern(for: pattern)
        regexPattern = regexPattern.replacingOccurrences(of: "\\*", with: ".*")

        guard let regex = try? NSRegularExpression(pattern: "^\(regexPattern)$") else {
            return false
        }

        let range = NSRange(url.startIndex..., in: url)
        return regex.firstMatch(in: url, range: range) != nil
    }

    // MARK: - Cleanup

    /// Removes all menu items for an extension (called on uninstall).
    func clearAllForExtension(_ extensionID: String) {
        removeAll(extensionID: extensionID)
    }
}
