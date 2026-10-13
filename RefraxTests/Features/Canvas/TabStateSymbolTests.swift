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
    func `a live device always wins the capture symbol over a muted one`() {
        #expect(TabStateSymbol.capture(isCameraLive: false, isCameraMuted: true, isMicrophoneLive: true, isMicrophoneMuted: false)
            == .microphone(isMuted: false))
        #expect(TabStateSymbol.capture(isCameraLive: true, isCameraMuted: false, isMicrophoneLive: false, isMicrophoneMuted: true)
            == .camera(isMuted: false))
        #expect(TabStateSymbol.capture(isCameraLive: true, isCameraMuted: false, isMicrophoneLive: true, isMicrophoneMuted: false)
            == .cameraAndMicrophone)
        #expect(TabStateSymbol.capture(isCameraLive: false, isCameraMuted: true, isMicrophoneLive: false, isMicrophoneMuted: true)
            == .camera(isMuted: true))
        #expect(TabStateSymbol.capture(isCameraLive: false, isCameraMuted: false, isMicrophoneLive: false, isMicrophoneMuted: true)
            == .microphone(isMuted: true))
        #expect(TabStateSymbol.capture(isCameraLive: false, isCameraMuted: false, isMicrophoneLive: false, isMicrophoneMuted: false) == nil)
    }

    @Test
    func `both live devices are named together and turned off together`() {
        let both = TabStateSymbol.capture(.cameraAndMicrophone)
        #expect(both.label == "Camera and microphone in use")
        #expect(both.help() == "Turn off camera and microphone")
    }

    @Test
    func `a live capture is never dropped by the two-symbol cap`() {
        for capture: TabStateSymbol.Capture in [.camera(isMuted: false), .microphone(isMuted: false), .cameraAndMicrophone] {
            let shown = TabStateSymbol.symbols(call: false, capture: capture, audio: false, isCrashed: true, isSuspended: true, isUnread: true)
            #expect(shown.count == 2)
            #expect(shown.contains(.capture(capture)))
        }
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
