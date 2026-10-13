import Testing
@testable import Refrax

struct TabStateSymbolTests {
    @Test
    func `a tab shows at most two symbols, in priority order`() {
        let all = TabStateSymbol.symbols(
            call: false, capture: .camera(isMuted: false), audio: false, isCrashed: true, isSuspended: true, isUnread: true,
        )
        #expect(all == [.call(isMuted: false), .capture(.camera(isMuted: false))])
        let quiet = TabStateSymbol.symbols(call: nil, capture: nil, audio: true, isCrashed: false, isSuspended: true, isUnread: true)
        #expect(quiet == [.audio(isMuted: true), .suspended])
        #expect(TabStateSymbol.symbols(call: nil, capture: nil, audio: nil, isCrashed: true, isSuspended: false, isUnread: true) == [.crashed, .unread])
        #expect(TabStateSymbol.symbols(call: nil, capture: nil, audio: nil, isCrashed: false, isSuspended: false, isUnread: false).isEmpty)
    }

    @Test
    func `sound offers mute, then pause under Option, and names the key only on the current tab`() {
        let playing = TabStateSymbol.audio(isMuted: false)
        #expect(playing.systemImage() == "speaker.wave.2.fill")
        #expect(playing.systemImage(optionIsDown: true) == "pause.fill")
        #expect(playing.help(isCurrentTab: true) == "Mute · ⌃M · ⌥-click to pause")
        #expect(playing.help() == "Mute · ⌥-click to pause")
        #expect(TabStateSymbol.audio(isMuted: true).help(isCurrentTab: true) == "Unmute · ⌃M")
        #expect(TabStateSymbol.suspended.help() == "Wake")
    }
}
