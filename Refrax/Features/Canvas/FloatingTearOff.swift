import AppKit
import SwiftUI

// MARK: - Cards Leaving the Window

extension TabCanvasManager {
    /// Moves `tab` into a new window from a menu, and a beam runs from where its card was to
    /// the new window.
    func moveFloatingTabToNewWindow(_ tab: Tab, in area: CGRect) {
        let source = cardFrame(for: tab, in: area).flatMap(screenRect(fromLayer:))
        guard let destination = tabManager.moveTabToNewWindow(tab, from: windowState)?.window?.frame, let source else { return }
        ScreenBeam.play(from: source, to: destination)
    }

    /// The card that shows `tab` on screen: the page card for the current page, else its
    /// floating card while it is visible.
    private func cardFrame(for tab: Tab, in area: CGRect) -> CGRect? {
        if tab.id == windowState.activeTabID {
            let frame = windowState.controlIsland.pageCardFrame
            return frame.isEmpty ? nil : frame
        }
        guard visibleFloatingTabs.contains(where: { $0.id == tab.id }) else { return nil }
        return floatingFrame(for: tab, in: area)
    }

    /// A rectangle of the floating layer (top-left origin in the content view) on screen.
    private func screenRect(fromLayer rect: CGRect) -> CGRect? {
        guard let window = windowState.window, let content = window.contentView else { return nil }
        let local = content.isFlipped ? rect : CGRect(x: rect.minX, y: content.bounds.height - rect.maxY, width: rect.width, height: rect.height)
        return window.convertToScreen(content.convert(local, to: nil))
    }
}
