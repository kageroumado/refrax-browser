import AppKit
import WebKit

/// Runs extensions' keyboard commands, the `commands` of their manifests, for key presses
/// Refrax's own shortcuts leave alone.
///
/// A command reaches the extension as `commands.onCommand`, or performs its action for
/// `_execute_action` and `_execute_browser_action`. WebKit parses each command's
/// `suggested_key` (`Ctrl` is ⌘ and `MacCtrl` is ⌃ on a Mac, as in Chrome) and matches events
/// against it. Only the extensions running in the window's active tab hear its keys, and not
/// on a site the user disabled the extension for.
///
/// The handler sees key presses before the main menu does, so a command on a menu's keys
/// or on keys macOS reserves (`Ctrl+Q` is ⌘Q) never runs: Quit, Close, Copy and Paste stay
/// Refrax's, as Chrome keeps them its own. Settings show such a command as conflicting.
final class ExtensionCommandHandler {
    /// A shortcut: its key, lowercased, and its modifiers among ⌘, ⌥, ⌃ and ⇧.
    struct Keys: Hashable {
        let key: String
        let modifiers: UInt

        init(key: String, modifiers: NSEvent.ModifierFlags) {
            self.key = key.lowercased()
            self.modifiers = modifiers.intersection([.command, .option, .control, .shift]).rawValue
        }
    }

    /// Keys macOS and every Mac browser keep for themselves, whatever the menu holds.
    static let reservedKeys: Set<Keys> = {
        let pairs: [(String, NSEvent.ModifierFlags)] = [
            ("q", .command), ("w", .command), ("w", [.command, .shift]), ("n", .command), ("n", [.command, .shift]),
            ("t", .command), ("t", [.command, .shift]), ("c", .command), ("v", .command), ("x", .command),
            ("a", .command), ("z", .command), ("z", [.command, .shift]), ("h", .command), ("h", [.command, .option]),
            ("m", .command), (",", .command), ("\t", .command), (" ", .command), ("`", .command),
        ]
        return Set(pairs.map { Keys(key: $0.0, modifiers: $0.1) })
    }()

    private unowned let extensionManager: ExtensionManager
    private let mainMenu: () -> NSMenu?

    /// - Parameters:
    ///   - extensionManager: Where the extensions run.
    ///   - mainMenu: The menu whose key equivalents commands may not take.
    init(extensionManager: ExtensionManager, mainMenu: @escaping () -> NSMenu? = { NSApp.mainMenu }) {
        self.extensionManager = extensionManager
        self.mainMenu = mainMenu
    }

    /// Performs the command `event` triggers in an extension running in `windowState`'s
    /// active tab. When two extensions claim the same keys, the first by name wins.
    ///
    /// - Returns: Whether a command ran, so the event should go no further.
    func perform(_ event: NSEvent, in windowState: WindowState?) -> Bool {
        guard event.type == .keyDown else { return false }
        let tab = windowState?.activeTab
        for context in contexts(for: tab) {
            guard let command = context.command(for: event), conflict(for: command) == nil else { continue }
            if let url = tab?.activePage.url, let installed = extensionManager.installedExtension(for: context),
               extensionManager.isExtensionDisabled(installed, for: url) {
                continue
            }
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

    /// What `command`'s keys belong to instead, a menu item's title or "macOS", or `nil` when
    /// the keys are free.
    func conflict(for command: WKWebExtension.Command) -> String? {
        Self.conflict(for: command, mainMenu: mainMenu())
    }

    /// What `command`'s keys belong to in `mainMenu` or among the reserved keys.
    static func conflict(for command: WKWebExtension.Command, mainMenu: NSMenu?) -> String? {
        guard let key = command.activationKey, !key.isEmpty else { return nil }
        let keys = Keys(key: key, modifiers: command.modifierFlags)
        if let title = mainMenu.flatMap({ title(of: keys, in: $0) }) {
            return title
        }
        return reservedKeys.contains(keys) ? "macOS" : nil
    }

    /// The title of the item in `menu` or its submenus whose key equivalent is `keys`.
    static func title(of keys: Keys, in menu: NSMenu) -> String? {
        for item in menu.items {
            if let submenu = item.submenu, let title = title(of: keys, in: submenu) {
                return title
            }
            guard !item.keyEquivalent.isEmpty else { continue }
            var modifiers = item.keyEquivalentModifierMask
            // An uppercase key equivalent means Shift.
            if item.keyEquivalent != item.keyEquivalent.lowercased() {
                modifiers.insert(.shift)
            }
            if Keys(key: item.keyEquivalent, modifiers: modifiers) == keys {
                return item.title
            }
        }
        return nil
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
