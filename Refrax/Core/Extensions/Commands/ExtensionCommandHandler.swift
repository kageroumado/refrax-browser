import AppKit
import WebKit

/// Runs extensions' keyboard commands, the `commands` of their manifests, for key presses
/// Refrax's own shortcuts leave alone.
///
/// A command reaches the extension as `commands.onCommand`, or performs its action for
/// `_execute_action` and `_execute_browser_action`. WebKit parses each command's
/// `suggested_key` (`Ctrl` is ⌘ and `MacCtrl` is ⌃ on a Mac, as in Chrome) and matches events
/// against it. Only the extensions running in the window's active tab hear its keys.
final class ExtensionCommandHandler {
    private unowned let extensionManager: ExtensionManager

    init(extensionManager: ExtensionManager) {
        self.extensionManager = extensionManager
    }

    /// Performs the command `event` triggers in an extension running in `windowState`'s
    /// active tab. When two extensions claim the same keys, the first by name wins.
    ///
    /// - Returns: Whether a command ran, so the event should go no further.
    func perform(_ event: NSEvent, in windowState: WindowState?) -> Bool {
        guard event.type == .keyDown else { return false }
        for context in contexts(for: windowState?.activeTab) where context.command(for: event) != nil {
            if context.performCommand(for: event) {
                Logger.debug(
                    "Extension command performed: \(context.webExtension.displayName ?? context.uniqueIdentifier)",
                    category: Logger.extensions,
                )
                return true
            }
        }
        return false
    }

    /// A command's keys as menus write them, such as `⇧⌘Y`, or `nil` when it has none.
    static func shortcut(for command: WKWebExtension.Command) -> String? {
        guard let key = command.activationKey, !key.isEmpty else { return nil }
        let flags = command.modifierFlags
        let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { flags.contains($0.0) }.map(\.1).joined() + key.uppercased()
    }

    private func contexts(for tab: Tab?) -> [WKWebExtensionContext] {
        let controller = tab.map(extensionManager.controller(for:)) ?? extensionManager.defaultController
        return controller.extensionContexts.sorted {
            ($0.webExtension.displayName ?? "").localizedStandardCompare($1.webExtension.displayName ?? "") == .orderedAscending
        }
    }
}
