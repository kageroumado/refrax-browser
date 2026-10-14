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
        /// A slide starts with this pan.
        case begin(CGSize)
        /// The slide follows this pan.
        case pan(CGSize)
        /// The fingers lifted; momentum may follow. Settle if it has not begun shortly.
        case liftOff
        /// The slide is over: the table springs to rest.
        case settle
        /// Finish table motion and deliver the new gesture’s first event to the page.
        case settleAndPass
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
        /// A released smooth wheel drains until its events go quiet.
        case smoothDraining
    }

    /// Momentum slower than this many points per event ends the slide where it is, instead
    /// of a long tail too slow to see.
    static let momentumSettleSpeed: CGFloat = 0.5

    private(set) var state = State.idle

    /// Whether a slide is underway, so its events stay with the table wherever the pointer is.
    var isSliding: Bool {
        switch state {
        case .tracking, .awaitingMomentum, .momentum, .draining, .smoothTracking, .smoothDraining: true
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
        state = .draining
        return .settle
    }

    /// A smooth wheel has gone quiet: settle its slide.
    mutating func smoothWheelWentQuiet() -> Decision {
        let wasTracking = state == .smoothTracking
        guard wasTracking || state == .smoothDraining else { return .consume }
        state = .idle
        return wasTracking ? .settle : .consume
    }

    /// A click, a key, ⌃ let go, or the window losing key ends the slide where it is. The
    /// rest of a gesture still under the fingers, and its momentum, are swallowed.
    mutating func interrupt() -> Decision {
        switch state {
        case .tracking, .momentum:
            state = .draining
            return .settle
        case .awaitingMomentum:
            state = .draining
            return .settle
        case .smoothTracking:
            state = .smoothDraining
            return .settle
        case .idle, .passing, .draining, .smoothDraining:
            return .consume
        }
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
        if state == .smoothDraining {
            return .consume
        }
        if state == .smoothTracking {
            return .pan(sample.delta)
        }
        guard controlDown, canStart else { return .pass }
        state = .smoothTracking
        return .begin(sample.delta)
    }

    private mutating func routeGesture(_ sample: Sample, controlDown: Bool, canStart: Bool) -> Decision {
        let phase = sample.phase
        if state == .draining, !phase.contains(.began), !phase.contains(.mayBegin) {
            if phase.contains(.cancelled) {
                state = .idle
            }
            return .consume
        }
        if phase.contains(.began) {
            if controlDown, canStart {
                state = .tracking
                return .begin(sample.delta)
            }
            let wasSliding = isSliding && state != .draining
            state = .passing
            return wasSliding ? .settleAndPass : .pass
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
                state = .draining
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
            if state == .draining {
                return .consume
            }
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

extension TableCamera {
    /// The slabs kept live at `viewpoint`: every slab in view and one slab beyond it on each
    /// side, in the rows in view and the row beyond each edge. Rows above and below take the
    /// slabs over the viewport's span the same way. Top row first, left to right; frames are
    /// in viewport coordinates and `isWhole` says the slab is entirely in view.
    func bandSlabs(in layout: TableLayout, at viewpoint: TableViewpoint) -> [TableVisibleSlab] {
        guard !layout.rows.isEmpty, viewport.width > 0, viewport.height > 0 else { return [] }
        let bounds = CGRect(origin: .zero, size: viewport)
        let first = max(Int(viewpoint.row.rounded(.down)) - 1, 0)
        let last = min(Int(viewpoint.row.rounded(.up)) + 1, layout.rows.count - 1)
        guard first <= last else { return [] }
        var result: [TableVisibleSlab] = []
        for rowIndex in first ... last {
            let row = layout.rows[rowIndex]
            let offset = drawnOffset(ofRow: rowIndex, in: layout, at: viewpoint)
            let y = CGFloat(Double(rowIndex) - viewpoint.row) * viewport.height
            let frames = row.slabs.indices.map { index in
                tableFrame(of: TableLayout.Position(row: rowIndex, slab: index), in: layout)
                    .offsetBy(dx: -offset, dy: y - CGFloat(rowIndex) * viewport.height)
            }
            let overlapping = frames.indices.filter { frames[$0].maxX > Self.wholeTolerance && frames[$0].minX < viewport.width - Self.wholeTolerance }
            guard let low = overlapping.first, let high = overlapping.last else { continue }
            for index in max(low - 1, 0) ... min(high + 1, frames.count - 1) {
                result.append(TableVisibleSlab(
                    position: TableLayout.Position(row: rowIndex, slab: index),
                    tabID: row.slabs[index].tabID,
                    frame: frames[index],
                    isWhole: bounds.insetBy(dx: -Self.wholeTolerance, dy: -Self.wholeTolerance).contains(frames[index]),
                ))
            }
        }
        return result
    }
}
