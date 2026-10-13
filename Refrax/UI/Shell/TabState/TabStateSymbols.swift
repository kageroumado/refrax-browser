import AppKit
import SwiftUI

/// A tab's live state as up to two small symbols beside its title: a call, the camera or
/// microphone, sound, a crash, suspension, unread. Each one is a button that acts on the state
/// it shows.
///
/// Symbols use the island's weight and the secondary style so they read as state, not as
/// controls asking to be pressed. Nothing animates except a symbol replacing itself when its
/// state changes, and Reduce Motion turns that into a plain swap.
///
/// An isolated observation view: page state changes invalidate only these symbols.
struct TabStateSymbols: View {
    let tab: Tab

    @Environment(WebPagePool.self) private var pagePool
    @Environment(WindowState.self) private var windowState
    @Environment(ModifierKeysState.self) private var modifierKeys
    @Environment(Sidebar.MediaControlsManager.self) private var mediaControls
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Layout {
        static let symbolSize: CGFloat = 11
        static let targetWidth: CGFloat = 18
        static let targetHeight: CGFloat = 22
        static let spacing: CGFloat = 2
    }

    private var control: TabMediaControl {
        TabMediaControl(tab: tab, pagePool: pagePool, mediaControls: mediaControls)
    }

    private var symbols: [TabStateSymbol] {
        let state = control.state
        return TabStateSymbol.symbols(
            for: state,
            isSuspended: state.isSuspended(createdAt: tab.createdAt),
            isUnread: tab.isUnread,
        )
    }

    var body: some View {
        let symbols = symbols
        if !symbols.isEmpty {
            HStack(spacing: Layout.spacing) {
                ForEach(symbols) { symbol in
                    button(for: symbol)
                }
            }
            .transaction { $0.animation = nil }
        }
    }

    private func button(for symbol: TabStateSymbol) -> some View {
        let optionIsDown = modifierKeys.isOptionPressed
        let isCurrent = tab.id == windowState.activeTabID
        let image = symbol.systemImage(optionIsDown: optionIsDown)
        return Button {
            perform(symbol)
        } label: {
            Image(systemName: image)
                .font(.system(size: Layout.symbolSize, weight: ControlIslandPlacement.symbolWeight))
                .foregroundStyle(.secondary)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .animation(reduceMotion ? nil : .default, value: image)
                .frame(width: Layout.targetWidth, height: Layout.targetHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(symbol.help(optionIsDown: optionIsDown, isCurrentTab: isCurrent))
        .accessibilityLabel(symbol.label)
        .accessibilityHint(symbol.help(isCurrentTab: isCurrent))
    }

    private func perform(_ symbol: TabStateSymbol) {
        let control = control
        switch symbol {
        case let .call(isMuted):
            control.setMuted(!isMuted)
        case let .capture(.camera(isMuted)):
            control.setCameraMuted(!isMuted)
        case let .capture(.microphone(isMuted)):
            control.setMicrophoneMuted(!isMuted)
        case let .audio(isMuted):
            if !isMuted, NSEvent.modifierFlags.contains(.option) {
                control.pauseMedia()
            } else {
                control.setMuted(!isMuted)
            }
        case .crashed:
            control.reload()
        case .suspended:
            control.wake()
        case .unread:
            tab.isUnread = false
            tab.unreadFromBadge = false
        }
    }
}
