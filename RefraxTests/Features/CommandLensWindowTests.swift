import AppKit
import Testing
@testable import Refrax

@Suite("Command Lens window")
@MainActor
struct CommandLensWindowTests {
    @Test
    func `The lens window takes the keyboard only while the lens is up`() {
        let window = CommandLensWindow()
        #expect(!window.canBecomeKey)
        window.isLensShown = true
        #expect(window.canBecomeKey)
        window.isLensShown = false
        #expect(!window.canBecomeKey)
        #expect(!window.canBecomeMain)
    }
}
