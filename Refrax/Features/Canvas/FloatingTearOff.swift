import AppKit
import SwiftUI

/// Where a card dragged out of its window goes, in screen coordinates (bottom-left origin).
///
/// A header drag tears the card off once the pointer is more than ``threshold`` points outside
/// the window. Released there, the tab becomes the page of a new window placed under the
/// pointer, and while it is outside a copy of the card follows the pointer.
nonisolated enum FloatingTearOff {
    /// How far past the window's frame the pointer goes before the card leaves.
    static let threshold: CGFloat = 24

    /// Whether `pointer` is far enough outside `windowFrame` for the card to leave.
    static func isTornOff(pointer: CGPoint, from windowFrame: CGRect) -> Bool {
        !windowFrame.insetBy(dx: -threshold, dy: -threshold).contains(pointer)
    }

    /// The card's copy under the pointer: `grab` is where the pointer holds the card, measured
    /// from the card's top-left corner.
    static func ghostFrame(pointer: CGPoint, grab: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: pointer.x - grab.x, y: pointer.y + grab.y - size.height, width: size.width, height: size.height)
    }

    /// The new window's frame: its title bar under the pointer, held at `grabFraction` of its
    /// width the way the card's header was, and kept inside `visibleFrame`.
    static func windowFrame(size: CGSize, pointer: CGPoint, grabFraction: CGFloat, titleBarHeight: CGFloat, within visibleFrame: CGRect) -> CGRect {
        let fraction = grabFraction.isFinite ? min(1, max(0, grabFraction)) : 0.5
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        let x = pointer.x - width * fraction
        let top = pointer.y + titleBarHeight / 2
        return CGRect(
            x: min(max(x, visibleFrame.minX), visibleFrame.maxX - width),
            y: min(max(top - height, visibleFrame.minY), visibleFrame.maxY - height),
            width: width,
            height: height,
        )
    }
}

/// The copy of a card that follows the pointer outside its window, in a borderless panel
/// that takes no clicks and casts the window shadow.
@MainActor
final class FloatingTearOffGhost {
    private let panel: PassThroughPanel
    private let grab: CGPoint
    private let size: CGSize

    /// The fraction of the card's width at which the pointer holds it.
    var grabFraction: CGFloat {
        size.width > 0 ? grab.x / size.width : 0.5
    }

    init(tab: Tab, snapshot: NSImage?, placement: FloatingTabPlacement, size: CGSize, grab: CGPoint) {
        self.grab = grab
        self.size = size
        self.panel = PassThroughPanel(frame: CGRect(origin: .zero, size: size), hasShadow: true)
        let favicon = tab.activePage.faviconData.flatMap(NSImage.init(data:))
        panel.contentView = NSHostingView(rootView: FloatingTearOffCard(
            title: tab.displayTitle, favicon: favicon, snapshot: placement.shape == .live ? snapshot : nil,
            shape: placement.shape, isKept: placement.isPinned,
        ).frame(width: size.width, height: size.height))
    }

    /// Follows `pointer`, shown while it is outside the window.
    func follow(_ pointer: CGPoint, isOutside: Bool) {
        guard isOutside else {
            panel.orderOut(nil)
            return
        }
        panel.setFrame(FloatingTearOff.ghostFrame(pointer: pointer, grab: grab, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func close() {
        panel.close()
    }
}

/// The card as it looks while it leaves: its header over the last snapshot of its page.
private struct FloatingTearOffCard: View {
    let title: String
    let favicon: NSImage?
    let snapshot: NSImage?
    let shape: FloatingCardShape
    let isKept: Bool

    private typealias Header = FloatingCardChrome.Header

    var body: some View {
        VStack(spacing: 0) {
            if shape == .icon {
                faviconImage
                    .frame(width: FloatingCardShape.Layout.iconFaviconSize, height: FloatingCardShape.Layout.iconFaviconSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: Header.itemSpacing) {
                    faviconImage
                        .frame(width: Header.glyphBox, height: Header.glyphBox)
                    Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Header.leadingPadding)
                .frame(height: Header.height)
            }
            if let snapshot {
                Image(nsImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipShape(.rect(cornerRadius: FloatingCardChrome.previewCornerRadius(isKept: isKept)))
                    .padding([.horizontal, .bottom], FloatingTabPlacement.previewInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial, in: .rect(cornerRadius: FloatingCardChrome.cornerRadius(for: shape, isKept: isKept), style: .continuous))
    }

    @ViewBuilder private var faviconImage: some View {
        if let favicon {
            Image(nsImage: favicon).resizable().scaledToFit()
        } else {
            Image(systemName: "globe")
        }
    }
}

// MARK: - Cards Leaving the Window

extension TabCanvasManager {
    /// Whether a header drag on `tab` can tear it off into a window of its own: a tab of a
    /// space, not a favorite.
    func canTearOff(_ tab: Tab) -> Bool {
        !tab.isFavorite && !tab.isArchived && tab.space != nil
    }

    /// Ends a header drag released outside the window: the card goes back to where the drag
    /// began, and the tab becomes the page of a new window under `pointer`.
    func tearOffFloatingCard(_ tab: Tab, at pointer: CGPoint, grabFraction: CGFloat, in area: CGRect) {
        if let origin = floatingMoveOrigins[tab.id] {
            var placement = floatingPlacement(for: tab)
            placement.move(to: origin, in: area)
            updateFloatingPlacement(placement, for: tab)
        }
        endFloatingMove()
        guard let window = tabManager.moveTabToNewWindow(tab, from: windowState)?.window else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? window.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let titleBarHeight = window.frame.height - window.contentLayoutRect.height
        window.setFrame(
            FloatingTearOff.windowFrame(
                size: window.frame.size, pointer: pointer, grabFraction: grabFraction,
                titleBarHeight: max(titleBarHeight, FloatingCardChrome.Header.height), within: visible,
            ),
            display: true,
        )
    }

    /// Moves `tab` into a new window from a menu, and a beam runs from where its card was to
    /// the new window.
    func moveFloatingTabToNewWindow(_ tab: Tab, in area: CGRect) {
        let source = cardFrame(for: tab, in: area).flatMap(screenRect(fromLayer:))
        guard let destination = tabManager.moveTabToNewWindow(tab, from: windowState)?.window?.frame, let source else { return }
        ScreenBeam.play(from: source, to: destination)
    }

    /// Keeps `tabs`' cards at least the island's adjacent gap away from its rail.
    func keepClearOfRail(_ tabs: [Tab], in area: CGRect) {
        guard showsFloatingControls else { return }
        let rail = windowState.controlIsland.railFrame
        guard !rail.isEmpty else { return }
        for tab in tabs {
            let placement = floatingPlacement(for: tab)
            var next = placement
            next.keepClear(of: rail, gap: ControlIslandPlacement.adjacentGap, in: area)
            if next != placement {
                updateFloatingPlacement(next, for: tab)
            }
        }
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
