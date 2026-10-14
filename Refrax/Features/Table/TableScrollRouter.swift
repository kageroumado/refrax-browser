import AppKit

/// What kind of device a scroll event comes from, which decides how it moves the table.
nonisolated enum TableScrollSource: Equatable, Sendable {
    /// A trackpad or Magic Mouse: phased gestures with momentum, panned 1:1.
    case trackpad
    /// A mouse with smooth scrolling: fine deltas with no gesture phases, panned 1:1 and
    /// settled once the events stop.
    case smoothWheel
    /// A notched mouse wheel: each event is one step.
    case wheel

    /// Classifies an event by its phases first: only gesture devices send them.
    static func classify(hasPreciseDeltas: Bool, phase: NSEvent.Phase, momentumPhase: NSEvent.Phase) -> Self {
        if !phase.isEmpty || !momentumPhase.isEmpty {
            return .trackpad
        }
        return hasPreciseDeltas ? .smoothWheel : .wheel
    }
}

/// Decides which scroll events slide the table instead of scrolling the page.
///
/// A gesture is claimed at its start: a trackpad gesture that begins with ⌃ down over the
/// page belongs to the table until its momentum ends, even if ⌃ is let go or the pointer
/// crosses a control. A gesture that begins without ⌃ stays the page's to its end. Notched
/// wheel events are judged one by one.
///
/// Deltas follow `NSEvent.scrollingDeltaX/Y`.
nonisolated struct TableScrollRouter: Equatable, Sendable {
    /// One scroll event, reduced to what the routing needs.
    struct Sample: Equatable, Sendable {
        var source: TableScrollSource
        var phase: NSEvent.Phase = []
        var momentumPhase: NSEvent.Phase = []
        var delta: CGSize
        var shift = false
    }

    /// What to do with a sample.
    enum Decision: Equatable, Sendable {
        /// The page receives the event.
        case pass
        /// The table swallows the event and does nothing with it.
        case consume
        /// A slide starts with this pan. Any peek of the floating tabs is cancelled.
        case begin(CGSize)
        /// The slide follows this pan.
        case pan(CGSize)
        /// The fingers lifted; momentum may follow. Settle if it has not begun shortly.
        case liftOff
        /// The slide is over: the table springs to rest.
        case settle
        /// One wheel notch: the table steps once.
        case step(TableDirection)
    }

    enum State: Equatable, Sendable {
        case idle
        /// A gesture the page owns, until it ends.
        case passing
        /// Fingers on the trackpad, sliding the table.
        case tracking
        /// The fingers lifted; momentum has not begun yet.
        case awaitingMomentum
        /// Momentum continues the slide.
        case momentum
        /// The slide settled early; the rest of its momentum is swallowed.
        case draining
        /// A smooth wheel is sliding the table.
        case smoothTracking
    }

    /// Momentum slower than this many points per event stops carrying the table, so the
    /// spring takes over instead of a long slow tail.
    static let momentumSettleSpeed: CGFloat = 1.5

    private(set) var state = State.idle

    /// Whether a slide is underway, so its events stay with the table wherever the pointer is.
    var isSliding: Bool {
        switch state {
        case .tracking, .awaitingMomentum, .momentum, .draining, .smoothTracking: true
        case .idle, .passing: false
        }
    }

    /// Routes one sample. `controlDown` is ⌃ held with the event; `canStart` says the pointer
    /// is over the page with nothing in the way of a slide.
    mutating func route(_ sample: Sample, controlDown: Bool, canStart: Bool) -> Decision {
        switch sample.source {
        case .wheel:
            return routeWheel(sample, controlDown: controlDown, canStart: canStart)
        case .smoothWheel:
            return routeSmoothWheel(sample, controlDown: controlDown, canStart: canStart)
        case .trackpad:
            if !sample.phase.isEmpty {
                return routeGesture(sample, controlDown: controlDown, canStart: canStart)
            }
            return routeMomentum(sample)
        }
    }

    /// The pause after lift-off has passed with no momentum: settle if still waiting.
    mutating func momentumWindowElapsed() -> Decision {
        guard state == .awaitingMomentum else { return .consume }
        state = .idle
        return .settle
    }

    /// A smooth wheel has gone quiet: settle its slide.
    mutating func smoothWheelWentQuiet() -> Decision {
        guard state == .smoothTracking else { return .consume }
        state = .idle
        return .settle
    }

    mutating func reset() {
        state = .idle
    }

    // MARK: - Private

    private mutating func routeWheel(_ sample: Sample, controlDown: Bool, canStart: Bool) -> Decision {
        if isSliding {
            state = .idle
        }
        guard controlDown, canStart else { return .pass }
        guard let step = TableDirection.wheelStep(deltaX: sample.delta.width, deltaY: sample.delta.height, shift: sample.shift) else {
            return .consume
        }
        return .step(step)
    }

    private mutating func routeSmoothWheel(_ sample: Sample, controlDown: Bool, canStart: Bool) -> Decision {
        if state == .smoothTracking {
            return .pan(sample.delta)
        }
        guard controlDown, canStart else { return .pass }
        state = .smoothTracking
        return .begin(sample.delta)
    }

    private mutating func routeGesture(_ sample: Sample, controlDown: Bool, canStart: Bool) -> Decision {
        let phase = sample.phase
        if phase.contains(.began) {
            if controlDown, canStart {
                state = .tracking
                return .begin(sample.delta)
            }
            let wasSliding = isSliding && state != .draining
            state = .passing
            return wasSliding ? .settle : .pass
        }
        if phase.contains(.changed) {
            return state == .tracking ? .pan(sample.delta) : .pass
        }
        if phase.contains(.ended) {
            switch state {
            case .tracking:
                state = .awaitingMomentum
                return .liftOff
            case .passing:
                state = .idle
                return .pass
            default:
                return .pass
            }
        }
        if phase.contains(.cancelled) {
            switch state {
            case .tracking:
                state = .idle
                return .settle
            case .passing:
                state = .idle
                return .pass
            default:
                return .pass
            }
        }
        // Fingers touching down stop any momentum still carrying the table.
        if phase.contains(.mayBegin) {
            switch state {
            case .awaitingMomentum, .momentum:
                state = .idle
                return .settle
            case .draining:
                state = .idle
                return .consume
            default:
                return .pass
            }
        }
        return state == .tracking ? .consume : .pass
    }

    private mutating func routeMomentum(_ sample: Sample) -> Decision {
        let phase = sample.momentumPhase
        if phase.contains(.began) {
            guard state == .awaitingMomentum else { return .pass }
            state = .momentum
            return .pan(sample.delta)
        }
        if phase.contains(.changed) {
            switch state {
            case .momentum:
                if max(abs(sample.delta.width), abs(sample.delta.height)) < Self.momentumSettleSpeed {
                    state = .draining
                    return .settle
                }
                return .pan(sample.delta)
            case .draining:
                return .consume
            default:
                return .pass
            }
        }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            switch state {
            case .momentum:
                state = .idle
                return .settle
            case .draining:
                state = .idle
                return .consume
            default:
                return .pass
            }
        }
        return .pass
    }
}

extension TableCamera {
    /// `viewpoint`, given in `old`'s terms, restated in `new`'s so the table looks the same:
    /// the row nearest the viewpoint is matched by ID and the shift absorbs the change in its
    /// resting offset. A view in flight keeps its place on screen when an edit retargets it.
    /// When that row is gone the view starts from `new` at rest.
    func rebased(_ viewpoint: TableViewpoint, from old: TableLayout, to new: TableLayout) -> TableViewpoint {
        guard !old.rows.isEmpty else { return .resting(on: new) }
        let anchorIndex = anchorRow(of: viewpoint, in: old)
        let anchor = old.rows[anchorIndex]
        guard let newIndex = new.rows.firstIndex(where: { $0.id == anchor.id }) else { return .resting(on: new) }
        return TableViewpoint(
            row: viewpoint.row + Double(newIndex - anchorIndex),
            shift: viewpoint.shift + CGFloat(anchor.offset - new.rows[newIndex].offset) * viewport.width,
        )
    }

    /// The frame of `tabID`'s slab in the viewport when `layout` rests, top-left origin; it
    /// may lie outside the viewport. `nil` when the tab is not on the table.
    func restingFrame(of tabID: UUID, in layout: TableLayout) -> CGRect? {
        guard let position = layout.position(of: tabID) else { return nil }
        let frame = tableFrame(of: position, in: layout)
        let offset = drawnOffset(ofRow: position.row, in: layout, at: .resting(on: layout))
        return CGRect(
            x: frame.minX - offset,
            y: CGFloat(position.row - layout.focusedRow) * viewport.height,
            width: frame.width,
            height: frame.height,
        )
    }

    /// Whether moving focus from `old` to `new` crosses more than one slab: past a neighbor
    /// along the row, or past the next row.
    static func isLongJump(from old: TableLayout.Position, to new: TableLayout.Position) -> Bool {
        old.row == new.row ? abs(old.slab - new.slab) > 1 : abs(old.row - new.row) > 1
    }
}
