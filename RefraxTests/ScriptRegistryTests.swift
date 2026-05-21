import Foundation
import Testing
import WebKit

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for ScriptRegistry functionality.
    @Tag static var scriptRegistry: Self
}

// MARK: - Registration Tests

@Suite("Script Registration", .tags(.scriptRegistry))
@MainActor
struct ScriptRegistrationTests {
    @Test("Register adds script to registry")
    func registerAddsScript() {
        let registry = ScriptRegistry()
        let script = WKUserScript(source: "console.log('test')", injectionTime: .atDocumentStart, forMainFrameOnly: true)

        let id = registry.register(script, source: .system(name: "test"))

        #expect(registry.count == 1)
        #expect(id != UUID())
    }

    @Test("Unregister removes script by ID")
    func unregisterRemovesScript() {
        let registry = ScriptRegistry()
        let script = WKUserScript(source: "console.log('test')", injectionTime: .atDocumentStart, forMainFrameOnly: true)

        let id = registry.register(script, source: .system(name: "test"))
        #expect(registry.count == 1)

        registry.unregister(id: id)
        #expect(registry.isEmpty)
    }

    @Test("UnregisterAll for source removes only matching scripts")
    func unregisterAllForSource() {
        let registry = ScriptRegistry()
        let script1 = WKUserScript(source: "console.log('1')", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let script2 = WKUserScript(source: "console.log('2')", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let script3 = WKUserScript(source: "console.log('3')", injectionTime: .atDocumentStart, forMainFrameOnly: true)

        registry.register(script1, source: .system(name: "gpc"))
        registry.register(script2, source: .extension(id: "ext1"))
        registry.register(script3, source: .system(name: "blocking"))

        #expect(registry.count == 3)

        registry.unregisterAll(for: .system(name: "gpc"))

        #expect(registry.count == 2)
        #expect(registry.activeSources.contains(.extension(id: "ext1")))
        #expect(registry.activeSources.contains(.system(name: "blocking")))
        #expect(!registry.activeSources.contains(.system(name: "gpc")))
    }

    @Test("UnregisterAll clears all scripts")
    func unregisterAllClearsAll() {
        let registry = ScriptRegistry()
        let script1 = WKUserScript(source: "console.log('1')", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let script2 = WKUserScript(source: "console.log('2')", injectionTime: .atDocumentStart, forMainFrameOnly: true)

        registry.register(script1, source: .system(name: "gpc"))
        registry.register(script2, source: .extension(id: "ext1"))

        #expect(registry.count == 2)

        registry.unregisterAll()

        #expect(registry.isEmpty)
        #expect(registry.activeSources.isEmpty)
    }
}

// MARK: - Priority Ordering Tests

@Suite("Script Priority Ordering", .tags(.scriptRegistry))
@MainActor
struct ScriptPriorityTests {
    @Test("Scripts are ordered by priority (lower first)")
    func scriptsOrderedByPriority() {
        let registry = ScriptRegistry()

        // Register in reverse priority order
        let highPriority = WKUserScript(source: "high", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let lowPriority = WKUserScript(source: "low", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let medPriority = WKUserScript(source: "med", injectionTime: .atDocumentStart, forMainFrameOnly: true)

        registry.register(highPriority, source: .agent(sessionID: UUID()), priority: 100)
        registry.register(lowPriority, source: .system(name: "gpc"), priority: 10)
        registry.register(medPriority, source: .extension(id: "ext"), priority: 50)

        // Apply to controller and verify order
        let controller = WKUserContentController()
        registry.apply(to: controller)

        let scripts = controller.userScripts
        #expect(scripts.count == 3)
        #expect(scripts[0].source == "low")
        #expect(scripts[1].source == "med")
        #expect(scripts[2].source == "high")
    }

    @Test("Same priority preserves registration order")
    func samePriorityPreservesOrder() {
        let registry = ScriptRegistry()

        let first = WKUserScript(source: "first", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let second = WKUserScript(source: "second", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let third = WKUserScript(source: "third", injectionTime: .atDocumentStart, forMainFrameOnly: true)

        registry.register(first, source: .system(name: "a"), priority: 50)
        registry.register(second, source: .system(name: "b"), priority: 50)
        registry.register(third, source: .system(name: "c"), priority: 50)

        let controller = WKUserContentController()
        registry.apply(to: controller)

        let scripts = controller.userScripts
        #expect(scripts.count == 3)
        #expect(scripts[0].source == "first")
        #expect(scripts[1].source == "second")
        #expect(scripts[2].source == "third")
    }

    @Test("Standard priority constants have correct ordering")
    func standardPriorityOrdering() {
        #expect(ScriptRegistry.Priority.system < ScriptRegistry.Priority.extension)
        #expect(ScriptRegistry.Priority.extension < ScriptRegistry.Priority.agent)
    }

    @Test("Apply clears existing scripts from controller")
    func applyClearsExistingScripts() {
        let controller = WKUserContentController()

        // Add a script directly
        let existingScript = WKUserScript(source: "existing", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        controller.addUserScript(existingScript)
        #expect(controller.userScripts.count == 1)

        // Apply empty registry
        let registry = ScriptRegistry()
        registry.apply(to: controller)

        #expect(controller.userScripts.isEmpty)
    }
}

// MARK: - Extension Helper Tests

@Suite("Extension Script Helpers", .tags(.scriptRegistry))
@MainActor
struct ExtensionHelperTests {
    @Test("registerExtensionScript uses extension priority")
    func extensionScriptUsesPriority() {
        let registry = ScriptRegistry()

        // Register system script first
        let systemScript = WKUserScript(source: "system", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        registry.register(systemScript, source: .system(name: "gpc"), priority: ScriptRegistry.Priority.system)

        // Register extension script
        let extScript = WKUserScript(source: "extension", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        registry.registerExtensionScript(extScript, extensionID: "my-extension")

        let controller = WKUserContentController()
        registry.apply(to: controller)

        // System should come before extension
        let scripts = controller.userScripts
        #expect(scripts.count == 2)
        #expect(scripts[0].source == "system")
        #expect(scripts[1].source == "extension")
    }

    @Test("unregisterExtension removes all scripts for extension")
    func unregisterExtensionRemovesAll() {
        let registry = ScriptRegistry()

        let script1 = WKUserScript(source: "ext1-a", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let script2 = WKUserScript(source: "ext1-b", injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        let script3 = WKUserScript(source: "ext2", injectionTime: .atDocumentStart, forMainFrameOnly: true)

        registry.registerExtensionScript(script1, extensionID: "ext1")
        registry.registerExtensionScript(script2, extensionID: "ext1")
        registry.registerExtensionScript(script3, extensionID: "ext2")

        #expect(registry.count == 3)

        registry.unregisterExtension("ext1")

        #expect(registry.count == 1)
        #expect(registry.activeSources.contains(.extension(id: "ext2")))
        #expect(!registry.activeSources.contains(.extension(id: "ext1")))
    }
}

// MARK: - Agent Helper Tests

@Suite("Agent Script Helpers", .tags(.scriptRegistry))
@MainActor
struct AgentHelperTests {
    @Test("registerAgentScript uses agent priority")
    func agentScriptUsesPriority() {
        let registry = ScriptRegistry()
        let sessionID = UUID()

        // Register extension script first
        let extScript = WKUserScript(source: "extension", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        registry.registerExtensionScript(extScript, extensionID: "ext")

        // Register agent script
        let agentScript = WKUserScript(source: "agent", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        registry.registerAgentScript(agentScript, sessionID: sessionID)

        let controller = WKUserContentController()
        registry.apply(to: controller)

        // Extension should come before agent
        let scripts = controller.userScripts
        #expect(scripts.count == 2)
        #expect(scripts[0].source == "extension")
        #expect(scripts[1].source == "agent")
    }

    @Test("unregisterAgentSession removes all scripts for session")
    func unregisterAgentSessionRemovesAll() {
        let registry = ScriptRegistry()
        let session1 = UUID()
        let session2 = UUID()

        let script1 = WKUserScript(source: "s1-a", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let script2 = WKUserScript(source: "s1-b", injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        let script3 = WKUserScript(source: "s2", injectionTime: .atDocumentStart, forMainFrameOnly: true)

        registry.registerAgentScript(script1, sessionID: session1)
        registry.registerAgentScript(script2, sessionID: session1)
        registry.registerAgentScript(script3, sessionID: session2)

        #expect(registry.count == 3)

        registry.unregisterAgentSession(session1)

        #expect(registry.count == 1)
        #expect(registry.activeSources.contains(.agent(sessionID: session2)))
        #expect(!registry.activeSources.contains(.agent(sessionID: session1)))
    }
}

// MARK: - Query Tests

@Suite("Script Registry Queries", .tags(.scriptRegistry))
@MainActor
struct QueryTests {
    @Test("registrations(for:) returns matching registrations")
    func registrationsForSource() {
        let registry = ScriptRegistry()

        let script1 = WKUserScript(source: "gpc", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let script2 = WKUserScript(source: "ext", injectionTime: .atDocumentStart, forMainFrameOnly: true)

        registry.register(script1, source: .system(name: "gpc"))
        registry.register(script2, source: .extension(id: "ext1"))

        let systemRegistrations = registry.registrations(for: .system(name: "gpc"))
        #expect(systemRegistrations.count == 1)
        #expect(systemRegistrations.first?.script.source == "gpc")

        let extRegistrations = registry.registrations(for: .extension(id: "ext1"))
        #expect(extRegistrations.count == 1)
        #expect(extRegistrations.first?.script.source == "ext")
    }

    @Test("activeSources returns all unique sources")
    func activeSourcesReturnsUnique() {
        let registry = ScriptRegistry()
        let sessionID = UUID()

        let script1 = WKUserScript(source: "1", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let script2 = WKUserScript(source: "2", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let script3 = WKUserScript(source: "3", injectionTime: .atDocumentStart, forMainFrameOnly: true)

        registry.register(script1, source: .system(name: "gpc"))
        registry.register(script2, source: .extension(id: "ext1"))
        registry.register(script3, source: .agent(sessionID: sessionID))

        let sources = registry.activeSources
        #expect(sources.count == 3)
        #expect(sources.contains(.system(name: "gpc")))
        #expect(sources.contains(.extension(id: "ext1")))
        #expect(sources.contains(.agent(sessionID: sessionID)))
    }
}

// MARK: - ScriptSource Tests

@Suite("ScriptSource Description", .tags(.scriptRegistry))
@MainActor
struct ScriptSourceTests {
    @Test("System source description format")
    func systemSourceDescription() {
        let source = ScriptRegistry.ScriptSource.system(name: "gpc")
        #expect(source.description == "system(gpc)")
    }

    @Test("Extension source description format")
    func extensionSourceDescription() {
        let source = ScriptRegistry.ScriptSource.extension(id: "my-extension-id")
        #expect(source.description == "extension(my-extension-id)")
    }

    @Test("Agent source description format truncates UUID")
    func agentSourceDescription() {
        let sessionID = UUID(uuidString: "12345678-1234-1234-1234-123456789012")!
        let source = ScriptRegistry.ScriptSource.agent(sessionID: sessionID)
        #expect(source.description == "agent(12345678)")
    }

    @Test("ScriptSource equality")
    func scriptSourceEquality() {
        let system1 = ScriptRegistry.ScriptSource.system(name: "gpc")
        let system2 = ScriptRegistry.ScriptSource.system(name: "gpc")
        let system3 = ScriptRegistry.ScriptSource.system(name: "other")

        #expect(system1 == system2)
        #expect(system1 != system3)

        let ext1 = ScriptRegistry.ScriptSource.extension(id: "ext1")
        let ext2 = ScriptRegistry.ScriptSource.extension(id: "ext1")
        let ext3 = ScriptRegistry.ScriptSource.extension(id: "ext2")

        #expect(ext1 == ext2)
        #expect(ext1 != ext3)

        let sessionID = UUID()
        let agent1 = ScriptRegistry.ScriptSource.agent(sessionID: sessionID)
        let agent2 = ScriptRegistry.ScriptSource.agent(sessionID: sessionID)
        let agent3 = ScriptRegistry.ScriptSource.agent(sessionID: UUID())

        #expect(agent1 == agent2)
        #expect(agent1 != agent3)
    }
}
