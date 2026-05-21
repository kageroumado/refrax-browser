import AppKit
import Foundation
import WebKit

/// Handles keyboard shortcuts for browser extensions.
///
/// `ExtensionCommandHandler` monitors keyboard events and triggers extension
/// commands when their registered shortcuts are pressed. It integrates with
/// WebKit's `WKWebExtensionContext.performCommand(for:)` API.
///
/// ## Command Registration
///
/// Extensions register commands via their manifest.json:
/// ```json
/// {
///   "commands": {
///     "_execute_action": {
///       "suggested_key": {
///         "default": "Ctrl+Shift+Y"
///       },
///       "description": "Activate the extension"
///     },
///     "toggle-feature": {
///       "suggested_key": {
///         "default": "Alt+Shift+U"
///       },
///       "description": "Toggle feature"
///     }
///   }
/// }
/// ```
///
/// ## Shortcut Priority
///
/// 1. Refrax system shortcuts take priority (e.g., Cmd+T, Cmd+L)
/// 2. Extension shortcuts are checked after system shortcuts
/// 3. If multiple extensions register the same shortcut, the first-enabled wins
///
/// ## User Customization
///
/// Users can override default shortcuts via extension settings. Customizations
/// are stored in `InstalledExtension` and persisted to disk.
final class ExtensionCommandHandler {
    // MARK: - Types

    /// Represents a registered command shortcut.
    struct CommandShortcut: Equatable {
        /// The extension's unique identifier.
        let extensionIdentifier: String

        /// The command ID (e.g., "_execute_action", "toggle-feature").
        let commandID: String

        /// The key equivalent (e.g., "y", "u").
        let key: String

        /// The required modifiers.
        let modifiers: NSEvent.ModifierFlags

        func hash(into hasher: inout Hasher) {
            hasher.combine(extensionIdentifier)
            hasher.combine(commandID)
            hasher.combine(key)
            hasher.combine(modifiers.rawValue)
        }
    }

    /// Result of attempting to handle a keyboard event.
    enum HandleResult {
        /// A command was triggered for an extension.
        case handled(extensionIdentifier: String, commandID: String)
        /// No extension command matched.
        case notHandled
    }

    // MARK: - Properties

    /// The extension manager for accessing contexts.
    private weak var extensionManager: ExtensionManager?

    /// Cache of registered shortcuts for quick lookup.
    private var registeredShortcuts: [CommandShortcut] = []

    /// User-customized shortcuts (extension ID -> command ID -> shortcut).
    private var customShortcuts: [String: [String: CommandShortcut]] = [:]

    // MARK: - Initialization

    /// Creates a command handler.
    ///
    /// - Parameter extensionManager: The extension manager.
    init(extensionManager: ExtensionManager) {
        self.extensionManager = extensionManager
    }

    // MARK: - Shortcut Handling

    /// Attempts to handle a keyboard event as an extension command.
    ///
    /// Uses WebKit's built-in `performCommand(for:)` which handles
    /// matching the event to registered commands.
    ///
    /// - Parameter event: The keyboard event.
    /// - Returns: The result of handling the event.
    func handleKeyDown(_ event: NSEvent) -> HandleResult {
        guard let extensionManager else { return .notHandled }

        // Try each enabled extension's context
        for ext in extensionManager.enabledExtensions {
            guard let context = extensionManager.context(for: ext) else { continue }

            // Let WebKit match the event to a command
            if context.performCommand(for: event) {
                Logger.debug(
                    "Extension command triggered: \(ext.displayName)",
                    category: Logger.extensions,
                )

                return .handled(
                    extensionIdentifier: ext.uniqueIdentifier,
                    commandID: "unknown", // WebKit handles the matching internally
                )
            }
        }

        return .notHandled
    }

    // MARK: - Shortcut Registration

    /// Refreshes the cached shortcut list from enabled extensions.
    func refreshShortcuts() {
        guard let extensionManager else { return }

        var shortcuts: [CommandShortcut] = []

        for ext in extensionManager.enabledExtensions {
            guard let context = extensionManager.context(for: ext) else { continue }

            // Get commands from the extension
            let commands = context.commands

            for command in commands {
                // Check for user-customized shortcut first
                if let custom = customShortcuts[ext.uniqueIdentifier]?[command.id] {
                    shortcuts.append(custom)
                    continue
                }

                // Use default shortcut from manifest
                if let shortcut = parseShortcut(
                    from: command,
                    extensionIdentifier: ext.uniqueIdentifier,
                ) {
                    shortcuts.append(shortcut)
                }
            }
        }

        registeredShortcuts = shortcuts
    }

    /// Parses a shortcut from a WKWebExtension.Command.
    private func parseShortcut(
        from command: WKWebExtension.Command,
        extensionIdentifier: String,
    ) -> CommandShortcut? {
        guard let activationKey = command.activationKey else { return nil }

        // Build modifier flags
        var modifiers = NSEvent.ModifierFlags()

        if command.modifierFlags.contains(.command) {
            modifiers.insert(.command)
        }
        if command.modifierFlags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if command.modifierFlags.contains(.option) {
            modifiers.insert(.option)
        }
        if command.modifierFlags.contains(.control) {
            modifiers.insert(.control)
        }

        return CommandShortcut(
            extensionIdentifier: extensionIdentifier,
            commandID: command.id,
            key: activationKey.lowercased(),
            modifiers: modifiers,
        )
    }

    // MARK: - User Customization

    /// Sets a custom shortcut for an extension command.
    ///
    /// - Parameters:
    ///   - shortcut: The custom shortcut, or nil to reset to default.
    ///   - extensionIdentifier: The extension's unique identifier.
    ///   - commandID: The command ID.
    func setCustomShortcut(
        _ shortcut: CommandShortcut?,
        for extensionIdentifier: String,
        commandID: String,
    ) {
        if customShortcuts[extensionIdentifier] == nil {
            customShortcuts[extensionIdentifier] = [:]
        }

        customShortcuts[extensionIdentifier]?[commandID] = shortcut
        refreshShortcuts()
    }

    /// Gets the current shortcut for a command (custom or default).
    ///
    /// - Parameters:
    ///   - extensionIdentifier: The extension's unique identifier.
    ///   - commandID: The command ID.
    /// - Returns: The current shortcut, or nil if not set.
    func currentShortcut(
        for extensionIdentifier: String,
        commandID: String,
    ) -> CommandShortcut? {
        // Check custom first
        if let custom = customShortcuts[extensionIdentifier]?[commandID] {
            return custom
        }

        // Return default
        return registeredShortcuts.first {
            $0.extensionIdentifier == extensionIdentifier && $0.commandID == commandID
        }
    }

    /// Checks if a shortcut conflicts with Refrax system shortcuts.
    ///
    /// - Parameter shortcut: The shortcut to check.
    /// - Returns: `true` if the shortcut conflicts with a system shortcut.
    func conflictsWithSystemShortcut(_ shortcut: CommandShortcut) -> Bool {
        let systemShortcuts: [(NSEvent.ModifierFlags, String)] = [
            (.command, "t"), // Cmd+T: Command lens
            (.command, "l"), // Cmd+L: Address lens
            ([.command, .shift], "["), // Cmd+Shift+[: Previous tab
            ([.command, .shift], "]"), // Cmd+Shift+]: Next tab
            (.command, "w"), // Cmd+W: Close tab
            (.command, "n"), // Cmd+N: New window
            ([.command, .shift], "n"), // Cmd+Shift+N: New private window
            (.command, "r"), // Cmd+R: Reload
            (.command, ","), // Cmd+,: Settings
        ]

        return systemShortcuts.contains { mods, key in
            shortcut.modifiers == mods && shortcut.key == key
        }
    }

    /// Returns all commands for an extension.
    ///
    /// - Parameter extensionIdentifier: The extension's unique identifier.
    /// - Returns: Array of (commandID, currentShortcut) tuples.
    func commands(for extensionIdentifier: String) -> [(id: String, shortcut: CommandShortcut?)] {
        guard let extensionManager,
              let ext = extensionManager.installedExtensions.first(where: { $0.uniqueIdentifier == extensionIdentifier }),
              let context = extensionManager.context(for: ext) else {
            return []
        }

        return context.commands.map { command in
            (
                id: command.id,
                shortcut: currentShortcut(for: extensionIdentifier, commandID: command.id),
            )
        }
    }
}

// MARK: - Shortcut Formatting

extension ExtensionCommandHandler.CommandShortcut {
    /// Returns a human-readable string representation of the shortcut.
    var displayString: String {
        var parts: [String] = []

        if modifiers.contains(.control) {
            parts.append("⌃")
        }
        if modifiers.contains(.option) {
            parts.append("⌥")
        }
        if modifiers.contains(.shift) {
            parts.append("⇧")
        }
        if modifiers.contains(.command) {
            parts.append("⌘")
        }

        parts.append(key.uppercased())

        return parts.joined()
    }
}
