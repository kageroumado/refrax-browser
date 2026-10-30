import Foundation
import Testing
@testable import Refrax

/// The File Island comes back where it was after a relaunch, coupled if it was coupled.
struct FileIslandPlacementPersistenceTests {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "FileIslandPlacementPersistenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }

    @Test @MainActor
    func `a moved island starts the next launch at the same placement`() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = FileIslandState(defaults: defaults)
        #expect(state.placement == nil)
        #expect(!state.isCoupled)

        state.placement = ControlIslandPlacement(x: 0, y: 0.35)
        state.savePlacement()

        let relaunched = FileIslandState(defaults: defaults)
        #expect(relaunched.placement == ControlIslandPlacement(x: 0, y: 0.35))
        #expect(!relaunched.isCoupled)
    }

    @Test @MainActor
    func `a coupled island starts the next launch coupled`() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = FileIslandState(defaults: defaults)
        state.placement = ControlIslandPlacement(x: 1, y: 0.6)
        state.isCoupled = true
        state.savePlacement()

        let relaunched = FileIslandState(defaults: defaults)
        #expect(relaunched.isCoupled)
        #expect(relaunched.placement == ControlIslandPlacement(x: 1, y: 0.6))

        relaunched.isCoupled = false
        relaunched.savePlacement()
        #expect(!FileIslandState(defaults: defaults).isCoupled)
        #expect(FileIslandState(defaults: defaults).placement == ControlIslandPlacement(x: 1, y: 0.6))
    }

    @Test @MainActor
    func `resetting the island forgets its saved placement`() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = FileIslandState(defaults: defaults)
        state.placement = ControlIslandPlacement(x: 0.5, y: 1)
        state.isCoupled = true
        state.savePlacement()

        state.placement = nil
        state.isCoupled = false
        state.savePlacement()

        let relaunched = FileIslandState(defaults: defaults)
        #expect(relaunched.placement == nil)
        #expect(!relaunched.isCoupled)
        #expect(defaults.object(forKey: "fileIsland.placement") == nil)
    }

    @Test @MainActor
    func `an island without defaults keeps its placement for the session only`() {
        let state = FileIslandState(defaults: nil)
        state.placement = ControlIslandPlacement(x: 0, y: 0)
        state.savePlacement()
        #expect(state.placement == ControlIslandPlacement(x: 0, y: 0))
        #expect(FileIslandState(defaults: nil).placement == nil)
    }
}
