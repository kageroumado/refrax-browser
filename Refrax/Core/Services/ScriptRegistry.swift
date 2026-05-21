import Foundation
import Observation
import WebKit

/// Central registry for all user scripts injected into web pages.
///
/// All sources of scripts (GPC, content blocking, extensions, agents)
/// register through this component to prevent conflicts and ensure
/// consistent ordering.
///
/// ## Usage
///
/// ```swift
/// let registry = ScriptRegistry()
///
/// // Register a system script
/// let id = registry.register(gpcScript, source: .system(name: "gpc"), priority: .system)
///
/// // Apply all registered scripts to a controller
/// registry.apply(to: userContentController)
///
/// // Unregister when done
/// registry.unregister(id: id)
/// ```
///
/// ## Script Ordering
///
/// Scripts are applied in ascending priority order (lower priority values
/// execute first). Standard priority tiers:
///
/// | Priority | Value | Usage |
/// |----------|-------|-------|
/// | `.system` | 10 | Core browser scripts (GPC, content blocking) |
/// | `.extension` | 50 | Browser extension content scripts |
/// | `.agent` | 100 | MCP agent injected scripts |
///
/// Within the same priority, scripts are applied in registration order.
@Observable
final class ScriptRegistry {
    // MARK: - Priority Constants

    /// Standard priority levels for script injection ordering.
    enum Priority {
        /// Core browser functionality scripts (GPC, content blocking).
        /// These run earliest to establish browser policies.
        static let system = 10

        /// Browser extension content scripts.
        /// Run after system scripts but before agent scripts.
        static let `extension` = 50

        /// MCP agent injected scripts.
        /// Run last to avoid interfering with page/extension behavior.
        static let agent = 100
    }

    // MARK: - Types

    /// A registered script with its metadata.
    struct Registration: Identifiable {
        let id: UUID
        let source: ScriptSource
        let script: WKUserScript
        let priority: Int
        let registrationOrder: UInt64
    }

    /// The source of a registered script.
    enum ScriptSource: Hashable {
        /// System scripts (GPC, content blocking, etc.)
        case system(name: String)

        /// Browser extension scripts.
        case `extension`(id: String)

        /// MCP agent session scripts.
        case agent(sessionID: UUID)
    }

    // MARK: - Properties

    private var registrations: [Registration] = []
    private var registrationCounter: UInt64 = 0

    /// The current number of registered scripts.
    var count: Int { registrations.count }

    /// Whether the registry has no registered scripts.
    var isEmpty: Bool { registrations.isEmpty }

    // MARK: - Registration

    /// Registers a user script with the specified source and priority.
    ///
    /// - Parameters:
    ///   - script: The user script to register.
    ///   - source: The source of the script (system, extension, or agent).
    ///   - priority: The injection priority (lower values execute first). Default is 100.
    /// - Returns: A unique identifier for unregistering the script.
    @discardableResult
    func register(
        _ script: WKUserScript,
        source: ScriptSource,
        priority: Int = 100,
    ) -> UUID {
        let id = UUID()
        let registration = Registration(
            id: id,
            source: source,
            script: script,
            priority: priority,
            registrationOrder: registrationCounter,
        )
        registrationCounter += 1
        registrations.append(registration)
        return id
    }

    // MARK: - Extension Registration

    /// Registers a browser extension content script.
    ///
    /// Use this method when loading scripts from `WKWebExtension` content scripts.
    /// Scripts are registered with `.extension` priority and the extension's identifier.
    ///
    /// - Parameters:
    ///   - script: The extension's content script.
    ///   - extensionID: The unique identifier of the extension.
    /// - Returns: A unique identifier for unregistering the script.
    @discardableResult
    func registerExtensionScript(_ script: WKUserScript, extensionID: String) -> UUID {
        register(script, source: .extension(id: extensionID), priority: Priority.extension)
    }

    /// Unregisters all scripts for a specific extension.
    ///
    /// Call this when an extension is disabled or uninstalled.
    ///
    /// - Parameter extensionID: The extension's unique identifier.
    func unregisterExtension(_ extensionID: String) {
        unregisterAll(for: .extension(id: extensionID))
    }

    // MARK: - Agent Registration

    /// Registers an MCP agent session script.
    ///
    /// Use this method when an agent injects scripts for automation or content access.
    /// Scripts are registered with `.agent` priority.
    ///
    /// - Parameters:
    ///   - script: The agent's injected script.
    ///   - sessionID: The agent session's unique identifier.
    /// - Returns: A unique identifier for unregistering the script.
    @discardableResult
    func registerAgentScript(_ script: WKUserScript, sessionID: UUID) -> UUID {
        register(script, source: .agent(sessionID: sessionID), priority: Priority.agent)
    }

    /// Unregisters all scripts for a specific agent session.
    ///
    /// Call this when an agent session ends.
    ///
    /// - Parameter sessionID: The agent session's unique identifier.
    func unregisterAgentSession(_ sessionID: UUID) {
        unregisterAll(for: .agent(sessionID: sessionID))
    }

    // MARK: - Unregistration

    /// Unregisters a script by its identifier.
    ///
    /// - Parameter id: The identifier returned from `register(_:source:priority:)`.
    func unregister(id: UUID) {
        registrations.removeAll { $0.id == id }
    }

    /// Unregisters all scripts from the specified source.
    ///
    /// - Parameter source: The source to unregister scripts for.
    func unregisterAll(for source: ScriptSource) {
        registrations.removeAll { $0.source == source }
    }

    /// Unregisters all scripts.
    func unregisterAll() {
        registrations.removeAll()
    }

    // MARK: - Queries

    /// Returns all registrations for a given source.
    ///
    /// - Parameter source: The source to filter by.
    /// - Returns: Array of registrations matching the source.
    func registrations(for source: ScriptSource) -> [Registration] {
        registrations.filter { $0.source == source }
    }

    /// Returns all sources that have registered scripts.
    var activeSources: Set<ScriptSource> {
        Set(registrations.map(\.source))
    }

    // MARK: - Application

    /// Rebuilds a user content controller with all registered scripts.
    ///
    /// This method:
    /// 1. Removes all existing user scripts from the controller
    /// 2. Adds scripts in priority order (ascending)
    /// 3. Within the same priority, maintains registration order
    ///
    /// - Parameter controller: The controller to update.
    func apply(to controller: WKUserContentController) {
        controller.removeAllUserScripts()

        let sorted = registrations.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.registrationOrder < rhs.registrationOrder
        }

        for registration in sorted {
            controller.addUserScript(registration.script)
        }
    }
}

// MARK: - ScriptSource Description

extension ScriptRegistry.ScriptSource: CustomStringConvertible {
    var description: String {
        switch self {
        case let .system(name):
            "system(\(name))"
        case let .extension(id):
            "extension(\(id))"
        case let .agent(sessionID):
            "agent(\(sessionID.uuidString.prefix(8)))"
        }
    }
}
