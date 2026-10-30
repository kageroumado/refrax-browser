import AppKit

/// Turns the reveal key + swipe or wheel on the page, or a swipe or wheel on the rail's page
/// icon, into steps between chips, ahead of the page.
///
/// ``CanvasPageGestures`` hands every scroll event in the window here first; what this takes
/// never reaches the page or the rail. A trackpad gesture claimed by the router steps once, in
/// the direction the fingers moved past a short distance, and the rest of the gesture and its
/// momentum are swallowed. A wheel notch is one step.
///
/// A scroll on the page icon needs no key: it holds the islands revealed the way the key
/// does, from its first step until the pointer leaves the icon (``TabIconScrollHold``), and
/// steps the same way.
@MainActor
final class IslandInput {
    private unowned let islands: IslandController
    private unowned let canvas: TabCanvasManager
    /// The rail's page icon in window content coordinates; nil while the rail is away or
    /// shows no page.
    private let tabIcon: () -> CGRect?
    private var router = TableScrollRouter()
    private var hold = TabIconScrollHold()
    private var travel = CGSize.zero
    private var hasStepped = false

    private enum Layout {
        /// How far the fingers move before a swipe counts.
        static let swipeDistance: CGFloat = 48
    }

    init(islands: IslandController, canvas: TabCanvasManager, tabIcon: @escaping () -> CGRect?) {
        self.islands = islands
        self.canvas = canvas
        self.tabIcon = tabIcon
    }

    var isSliding: Bool {
        router.isSliding
    }

    /// A scroll on the page icon is holding the islands revealed.
    var holdsOnTabIcon: Bool {
        hold.isHolding
    }

    /// Routes a scroll event. `point` is the pointer in window content coordinates;
    /// `eligible` says the window's state lets the islands reveal, `overControls` that the
    /// pointer is over the rail, an island or a card. Returns `true` when the islands took it.
    func route(_ event: NSEvent, at point: CGPoint, eligible: @autoclosure () -> Bool, overControls: @autoclosure () -> Bool) -> Bool {
        let sample = TableScrollRouter.Sample(
            source: TableScrollSource.classify(
                hasPreciseDeltas: event.hasPreciseScrollingDeltas, phase: event.phase, momentumPhase: event.momentumPhase,
            ),
            phase: event.phase,
            momentumPhase: event.momentumPhase,
            delta: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY),
            shift: event.modifierFlags.contains(.shift),
        )
        let keyHeld = FloatingRevealKey.current.matchesHold(event.modifierFlags.intersection([.control, .option, .command]))
        return route(sample, keyHeld: keyHeld, at: point, eligible: eligible, overControls: overControls)
    }

    /// Routes one sample: a slide or a step begins over the page with the key down, or over
    /// the page icon with or without it.
    func route(_ sample: TableScrollRouter.Sample, keyHeld: Bool, at point: CGPoint, eligible: () -> Bool, overControls: () -> Bool) -> Bool {
        syncHold()
        let overIcon = hold.claims(point, icon: tabIcon())
        let mayStart = islands.currentTab != nil && eligible() && (overIcon || (keyHeld && !overControls()))
        switch router.route(sample, controlDown: keyHeld || overIcon, canStart: mayStart) {
        case .pass:
            return false
        case .settleAndPass:
            reset()
            return false
        case .consume, .liftOff:
            return true
        case .settle:
            reset()
            return true
        case let .begin(delta):
            holdIfOnIcon(overIcon)
            travel = .zero
            hasStepped = false
            accumulate(delta)
            return true
        case let .pan(delta):
            accumulate(delta)
            return true
        case let .step(direction):
            holdIfOnIcon(overIcon)
            islands.step(direction)
            return true
        }
    }

    /// The pointer is at `point`, in window content coordinates. A hold on the page icon
    /// ends when the pointer leaves the icon: the islands are let go as when the key is
    /// released, unless the key is down, which keeps them. The rest of a gesture under way
    /// and its momentum are swallowed.
    func pointerMoved(to point: CGPoint, keyHeld: Bool) {
        syncHold()
        guard hold.pointerMoved(to: point, icon: tabIcon()) else { return }
        _ = router.interrupt()
        reset()
        if !keyHeld {
            canvas.releaseFloatingTabs()
        }
    }

    /// A click, a key, the key let go, or the window losing key ends the gesture and any hold
    /// on the page icon; the caller lets the islands go.
    func interrupt() {
        _ = router.interrupt()
        _ = hold.end()
        reset()
    }

    /// A slide or a step on the page icon holds the islands revealed from here on.
    private func holdIfOnIcon(_ overIcon: Bool) {
        guard overIcon, hold.begin() else { return }
        canvas.revealFloatingTabs()
    }

    /// The reveal the hold kept was let go by someone else (the key, a click, a shortcut):
    /// the hold is over with it.
    private func syncHold() {
        if hold.isHolding, !canvas.floatingVisibility.isHeld {
            _ = hold.end()
        }
    }

    private func accumulate(_ delta: CGSize) {
        guard !hasStepped else { return }
        travel.width += delta.width
        travel.height += delta.height
        let direction: TableDirection?
        if abs(travel.width) >= Layout.swipeDistance, abs(travel.width) >= abs(travel.height) {
            // Fingers moving left bring the chip on the right into view.
            direction = travel.width < 0 ? .right : .left
        } else if abs(travel.height) >= Layout.swipeDistance {
            direction = travel.height < 0 ? .down : .up
        } else {
            direction = nil
        }
        if let direction {
            hasStepped = true
            islands.step(direction)
        }
    }

    private func reset() {
        travel = .zero
        hasStepped = false
    }
}
