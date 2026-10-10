import CoreGraphics
import Foundation

/// Tiles as rigid glass slabs sliding on a finite desk.
///
/// Every tile is an axis-aligned box that keeps its size and never overlaps another
/// at rest. Its collision box is the tile plus the title strip above it plus a small
/// gap, so titles never collide with tiles. A **held** tile (the one under the
/// pointer, or the members of a zone or magnet being carried) has infinite mass: it
/// goes where it is put and pushes everything in its way, passing its speed on to
/// what it hits. Released tiles slide with friction until they rest.
///
/// The desk has no walls. A tile whose center leaves it falls off, which is how a
/// full desk sheds tiles: pushing a crowd against an edge drops the outermost one.
///
/// The world is stepped in fixed substeps, so behavior does not depend on the
/// display's refresh rate. Each substep integrates velocities, then runs a few
/// passes of pairwise separation along the axis of least overlap, with an impulse
/// that removes the closing speed and adds a little bounce.
struct CanvasPhysics {
    /// One tile on the desk.
    struct Body: Equatable {
        /// The tile's rectangle, without its title.
        var frame: CGRect
        /// Board points per second.
        var velocity: CGPoint = .zero
        /// Positioned from outside and immovable by collisions.
        var isHeld = false
        /// Being simulated; sleeping bodies only move when something hits them.
        var isAwake = true
        /// Moved by the simulation since it last came to rest.
        var hasMoved = false
        /// Let go by the user, so its resting place is a drop.
        var wasDropped = false
        /// Seconds since a held body was last moved by its hand.
        var heldIdle: CGFloat = 0
        /// Seconds awake without the user acting on the desk.
        var unattendedTime: CGFloat = 0
    }

    /// What happened during a step.
    enum Event: Equatable {
        /// A tile came to rest somewhere new. `dropped` when the user let go of it.
        case settled(Tab.ID, frame: CGRect, dropped: Bool)
        /// A tile's center left the desk; it is gone from the world.
        case fell(Tab.ID)
    }

    enum Constants {
        /// Simulation substep.
        static let substep: CGFloat = 1.0 / 120
        /// Longest stretch simulated per call, so a stall does not teleport tiles.
        static let maximumStep: CGFloat = 1.0 / 20
        /// Separation passes per substep.
        static let iterations = 4
        /// Velocity decay per second: v · e^(−friction · dt).
        static let friction: CGFloat = 4.5
        /// Below this speed a body that touches nothing comes to rest.
        static let restSpeed: CGFloat = 30
        /// Fraction of closing speed returned as bounce.
        static let restitution: CGFloat = 0.25
        /// Room kept above a tile for its title.
        static let titleHeight: CGFloat = 24
        /// Smallest gap kept between two resting tiles.
        static let gap: CGFloat = 16
        /// Overlap this small counts as touching-but-apart, so rounding noise cannot
        /// keep two tiles that were just separated awake.
        static let slop: CGFloat = 1
        /// How far inside the far edges a stopped center is kept; `CGRect.contains`
        /// counts the max edges as outside.
        static let edgeMargin: CGFloat = 1
        /// A held tile moving at least this fast parts what it meets; slower, it pushes.
        static let partingSpeed: CGFloat = 30
        /// How fast a parted tile slides aside, as a multiple of the hand's speed.
        static let partingRatio: CGFloat = 2
        /// Sideways speed a parted tile keeps, as a fraction of the hand's speed.
        static let partingGlide: CGFloat = 0.1
        /// Time constant of a held body's measured speed: it is smoothed over pointer
        /// events and fades when the pointer stops, so a still hand pushes nothing.
        static let heldVelocityTimeConstant: CGFloat = 0.05
        /// Longest a tile keeps working its way free with nobody acting on the desk.
        /// A desk holding more tiles than fit leaves the rest overlapping after this.
        static let unattendedSettleTime: CGFloat = 2
        /// A hand unmoved for longer than this has stopped; pointer events arrive at
        /// least this often while it moves.
        static let heldIdleThreshold: CGFloat = 1.0 / 30
    }

    let desk: CGRect
    private(set) var bodies: [Tab.ID: Body] = [:]
    private var accumulator: CGFloat = 0

    init(desk: CGRect) {
        self.desk = desk
    }

    /// Whether stepping would change anything.
    var isRunning: Bool {
        bodies.values.contains { $0.isAwake || $0.isHeld }
    }

    /// Whether the simulation currently owns this tile's position.
    func isActive(_ id: Tab.ID) -> Bool {
        guard let body = bodies[id] else { return false }
        return body.isHeld || body.isAwake
    }

    // MARK: - Bodies

    /// Puts a tile at `frame`, adding it when new. A new or moved tile is woken so
    /// anything it now overlaps is pushed apart.
    mutating func place(_ id: Tab.ID, frame: CGRect) {
        if var body = bodies[id] {
            guard !body.isHeld, body.frame != frame else { return }
            body.frame = frame
            body.velocity = .zero
            body.isAwake = true
            body.unattendedTime = 0
            bodies[id] = body
        } else {
            bodies[id] = Body(frame: frame)
        }
    }

    mutating func remove(_ id: Tab.ID) {
        bodies[id] = nil
    }

    /// Moves a held tile to `frame`, holding it first if needed. Its velocity is
    /// estimated from the move, so whatever it hits inherits the motion.
    mutating func drag(_ id: Tab.ID, to frame: CGRect, elapsed: CGFloat) {
        guard var body = bodies[id] else { return }
        let dx = frame.minX - body.frame.minX
        let dy = frame.minY - body.frame.minY
        if body.isHeld, elapsed > 0 {
            // Smooth over pointer jitter: blend toward the latest per-move speed.
            let blend = 1 - exp(-elapsed / Constants.heldVelocityTimeConstant)
            body.velocity.x += (dx / elapsed - body.velocity.x) * blend
            body.velocity.y += (dy / elapsed - body.velocity.y) * blend
        } else {
            body.velocity = .zero
        }
        body.frame = frame
        body.isHeld = true
        body.isAwake = true
        body.heldIdle = 0
        bodies[id] = body
    }

    /// Lets go of a held tile with `velocity`. A dropped tile reports where it lands;
    /// a carried one does not, since whoever carried it already knows.
    mutating func release(_ id: Tab.ID, velocity: CGPoint, dropped: Bool) {
        guard var body = bodies[id] else { return }
        body.isHeld = false
        body.isAwake = true
        body.velocity = velocity
        body.hasMoved = dropped
        body.wasDropped = dropped
        bodies[id] = body
    }

    // MARK: - Stepping

    /// Advances the world by `elapsed` seconds.
    mutating func step(_ elapsed: CGFloat) -> [Event] {
        accumulator = min(accumulator + elapsed, Constants.maximumStep)
        var events: [Event] = []
        while accumulator >= Constants.substep {
            accumulator -= Constants.substep
            events += substep(Constants.substep)
        }
        return events
    }

    private mutating func substep(_ dt: CGFloat) -> [Event] {
        integrate(dt)
        var touching = Set<Tab.ID>()
        for _ in 0 ..< Constants.iterations {
            touching.formUnion(separate())
        }
        return finish(touching: touching, dt: dt)
    }

    private mutating func integrate(_ dt: CGFloat) {
        let decay = exp(-Constants.friction * dt)
        let heldDecay = exp(-dt / Constants.heldVelocityTimeConstant)
        for (id, var body) in bodies where body.isHeld {
            body.heldIdle += dt
            if body.heldIdle > Constants.heldIdleThreshold {
                body.velocity.x *= heldDecay
                body.velocity.y *= heldDecay
            }
            bodies[id] = body
        }
        for (id, var body) in bodies where body.isAwake && !body.isHeld {
            body.frame.origin.x += body.velocity.x * dt
            body.frame.origin.y += body.velocity.y * dt
            if !body.wasDropped {
                stopAtEdge(&body)
            }
            body.velocity.x *= decay
            body.velocity.y *= decay
            if body.velocity != .zero {
                body.hasMoved = true
            }
            bodies[id] = body
        }
    }

    /// Stops a knocked tile whose center reached the desk's edge. Only a tile the user
    /// let go of slides off by its own speed; one set moving by a collision never does.
    private func stopAtEdge(_ body: inout Body) {
        let center = CGPoint(x: body.frame.midX, y: body.frame.midY)
        let clamped = CGPoint(
            x: min(max(center.x, desk.minX), desk.maxX - Constants.edgeMargin),
            y: min(max(center.y, desk.minY), desk.maxY - Constants.edgeMargin),
        )
        if clamped.x != center.x {
            body.frame.origin.x += clamped.x - center.x
            body.velocity.x = 0
        }
        if clamped.y != center.y {
            body.frame.origin.y += clamped.y - center.y
            body.velocity.y = 0
        }
    }

    /// One pass of pairwise separation. Returns the bodies that touched something.
    private mutating func separate() -> Set<Tab.ID> {
        // Sweep along x: after sorting by the boxes' left edges, a body can only
        // overlap those that start before it ends.
        let order = bodies.map { (id: $0.key, box: Self.collisionBox($0.value.frame)) }
            .sorted { ($0.box.minX, $0.id.uuidString) < ($1.box.minX, $1.id.uuidString) }
        var touching = Set<Tab.ID>()

        for i in order.indices {
            for j in (i + 1) ..< order.count {
                guard order[j].box.minX < order[i].box.maxX else { break }
                let (idA, idB) = (order[i].id, order[j].id)
                guard var a = bodies[idA], var b = bodies[idB],
                      a.isAwake || a.isHeld || b.isAwake || b.isHeld else { continue }
                if resolve(&a, &b) {
                    bodies[idA] = a
                    bodies[idB] = b
                    touching.insert(idA)
                    touching.insert(idB)
                }
            }
        }
        return touching
    }

    /// Separates two overlapping bodies. Returns false when they do not overlap.
    private func resolve(_ a: inout Body, _ b: inout Body) -> Bool {
        guard Self.overlap(a.frame, b.frame) != nil else { return false }
        if a.isHeld, !b.isHeld, Self.speed(a.velocity) >= Constants.partingSpeed {
            part(&b, around: a)
        } else if b.isHeld, !a.isHeld, Self.speed(b.velocity) >= Constants.partingSpeed {
            part(&a, around: b)
        } else {
            collide(&a, &b)
        }
        Self.nudge(&a)
        Self.nudge(&b)
        return true
    }

    /// Overlap of two tiles' collision boxes on each axis, or nil when they are apart.
    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGSize? {
        let boxA = collisionBox(a)
        let boxB = collisionBox(b)
        let overlapX = min(boxA.maxX, boxB.maxX) - max(boxA.minX, boxB.minX)
        let overlapY = min(boxA.maxY, boxB.maxY) - max(boxA.minY, boxB.minY)
        guard overlapX > Constants.slop, overlapY > Constants.slop else { return nil }
        return CGSize(width: overlapX, height: overlapY)
    }

    private static func speed(_ velocity: CGPoint) -> CGFloat {
        hypot(velocity.x, velocity.y)
    }

    /// A moving hand parts what it meets, the way a hand sweeps through paper: the
    /// free tile slides sideways out of the hand's path at a rate tied to the hand's
    /// speed, and is plowed forward only as far as it must be to stay clear. Pushing
    /// straight ahead instead would bulldoze every tile in line before the hand.
    private func part(_ free: inout Body, around hand: Body) {
        let handBox = Self.collisionBox(hand.frame)
        let freeBox = Self.collisionBox(free.frame)
        let handSpeed = Self.speed(hand.velocity)
        let movesAlongX = abs(hand.velocity.x) >= abs(hand.velocity.y)

        // Sideways is perpendicular to the hand's motion, toward the side of the hand's
        // centerline the free tile is on; dead center breaks toward +. Parting never
        // drops a tile: when that side would carry its center off the desk, it goes the
        // other way. Falling off takes a push straight at the edge.
        func clearance(toward side: CGFloat) -> CGFloat {
            if movesAlongX {
                side > 0 ? handBox.maxY - freeBox.minY : freeBox.maxY - handBox.minY
            } else {
                side > 0 ? handBox.maxX - freeBox.minX : freeBox.maxX - handBox.minX
            }
        }
        func staysOnDesk(toward side: CGFloat) -> Bool {
            let shift = side * clearance(toward: side)
            let center = movesAlongX
                ? CGPoint(x: free.frame.midX, y: free.frame.midY + shift)
                : CGPoint(x: free.frame.midX + shift, y: free.frame.midY)
            return desk.contains(center)
        }
        var side: CGFloat = movesAlongX
            ? (freeBox.midY >= handBox.midY ? 1 : -1)
            : (freeBox.midX >= handBox.midX ? 1 : -1)
        if !staysOnDesk(toward: side), staysOnDesk(toward: -side) {
            side = -side
        }
        let clearance = clearance(toward: side)
        // Per substep: the forward plow below clears the contact in the first pass, so
        // later passes of the same substep never see it.
        let step = min(clearance, Constants.partingRatio * handSpeed * Constants.substep)
        if movesAlongX {
            free.frame.origin.y += side * step
            free.velocity.y = side * max(side * free.velocity.y, Constants.partingGlide * handSpeed)
        } else {
            free.frame.origin.x += side * step
            free.velocity.x = side * max(side * free.velocity.x, Constants.partingGlide * handSpeed)
        }

        // Whatever still overlaps is plowed out along the shallower axis, by position
        // alone, so the tile carries no forward speed once the hand has passed.
        guard let remaining = Self.overlap(free.frame, hand.frame) else { return }
        let alongX = CGPoint(x: (freeBox.midX >= handBox.midX ? 1 : -1) * remaining.width, y: 0)
        let alongY = CGPoint(x: 0, y: (freeBox.midY >= handBox.midY ? 1 : -1) * remaining.height)
        var shift = remaining.width < remaining.height ? alongX : alongY
        let other = remaining.width < remaining.height ? alongY : alongX
        if !desk.contains(CGPoint(x: free.frame.midX + shift.x, y: free.frame.midY + shift.y)),
           desk.contains(CGPoint(x: free.frame.midX + other.x, y: free.frame.midY + other.y)) {
            shift = other
        }
        free.frame.origin.x += shift.x
        free.frame.origin.y += shift.y
    }

    /// Pushes two overlapping bodies apart along the axis they overlap least on, and
    /// removes their closing speed along it.
    private func collide(_ a: inout Body, _ b: inout Body) {
        let boxA = Self.collisionBox(a.frame)
        let boxB = Self.collisionBox(b.frame)
        guard let overlap = Self.overlap(a.frame, b.frame) else { return }
        let overlapX = overlap.width
        let overlapY = overlap.height

        let inverseMassA: CGFloat = a.isHeld ? 0 : 1
        let inverseMassB: CGFloat = b.isHeld ? 0 : 1
        let totalInverseMass = inverseMassA + inverseMassB
        guard totalInverseMass > 0 else { return }

        // Normal from a to b on the axis of least penetration. Coincident centers
        // break the tie toward +x so stacked tiles still come apart. When that axis
        // would push a free tile's center off the desk and the other would not, the
        // other is taken: a tile falls to a collision only when it has no room.
        let alongX = (normal: CGPoint(x: boxB.midX >= boxA.midX ? 1 : -1, y: 0), depth: overlapX)
        let alongY = (normal: CGPoint(x: 0, y: boxB.midY >= boxA.midY ? 1 : -1), depth: overlapY)
        func dropsATile(_ axis: (normal: CGPoint, depth: CGFloat)) -> Bool {
            let shareA = axis.depth * inverseMassA / totalInverseMass
            let shareB = axis.depth * inverseMassB / totalInverseMass
            let centerA = CGPoint(x: a.frame.midX - axis.normal.x * shareA, y: a.frame.midY - axis.normal.y * shareA)
            let centerB = CGPoint(x: b.frame.midX + axis.normal.x * shareB, y: b.frame.midY + axis.normal.y * shareB)
            return (inverseMassA > 0 && !desk.contains(centerA)) || (inverseMassB > 0 && !desk.contains(centerB))
        }
        var (normal, depth) = overlapX < overlapY ? alongX : alongY
        let other = overlapX < overlapY ? alongY : alongX
        if dropsATile((normal, depth)), !dropsATile(other) {
            (normal, depth) = other
        }

        let shareA = depth * inverseMassA / totalInverseMass
        let shareB = depth * inverseMassB / totalInverseMass
        a.frame.origin.x -= normal.x * shareA
        a.frame.origin.y -= normal.y * shareA
        b.frame.origin.x += normal.x * shareB
        b.frame.origin.y += normal.y * shareB

        let closingSpeed = (b.velocity.x - a.velocity.x) * normal.x + (b.velocity.y - a.velocity.y) * normal.y
        if closingSpeed < 0 {
            let impulse = -(1 + Constants.restitution) * closingSpeed / totalInverseMass
            a.velocity.x -= impulse * inverseMassA * normal.x
            a.velocity.y -= impulse * inverseMassA * normal.y
            b.velocity.x += impulse * inverseMassB * normal.x
            b.velocity.y += impulse * inverseMassB * normal.y
        }
    }

    /// Wakes a body that was pushed, so it is simulated and reports where it rests.
    private static func nudge(_ body: inout Body) {
        guard !body.isHeld else { return }
        body.isAwake = true
        body.hasMoved = true
    }

    /// Drops bodies that left the desk and puts slow, untouched ones to rest.
    ///
    /// Falling closes a tab, so it happens only while the user is acting on the desk:
    /// a tile is held, or one they let go of is still moving. When the desk settles
    /// on its own (opening the canvas, tiles placed for new tabs), a tile with no room
    /// stops at the edge, and tiles still pressing on each other after
    /// ``Constants/unattendedSettleTime`` rest where they are.
    private mutating func finish(touching: Set<Tab.ID>, dt: CGFloat) -> [Event] {
        let userIsActing = bodies.values.contains { $0.isHeld || ($0.isAwake && $0.wasDropped) }
        var events: [Event] = []
        for (id, var body) in bodies where body.isAwake && !body.isHeld {
            if !desk.contains(CGPoint(x: body.frame.midX, y: body.frame.midY)) {
                if userIsActing {
                    bodies[id] = nil
                    events.append(.fell(id))
                    continue
                }
                stopAtEdge(&body)
            }
            body.unattendedTime = userIsActing ? 0 : body.unattendedTime + dt
            let isStuck = body.unattendedTime >= Constants.unattendedSettleTime
            guard isStuck || (!touching.contains(id) && hypot(body.velocity.x, body.velocity.y) < Constants.restSpeed) else {
                bodies[id] = body
                continue
            }
            body.velocity = .zero
            body.isAwake = false
            if body.hasMoved {
                body.frame.origin = CGPoint(x: body.frame.minX.rounded(), y: body.frame.minY.rounded())
                events.append(.settled(id, frame: body.frame, dropped: body.wasDropped))
            }
            body.hasMoved = false
            body.wasDropped = false
            bodies[id] = body
        }
        return events
    }

    /// The space a tile claims: itself, its title above it, and half the gap all round.
    static func collisionBox(_ frame: CGRect) -> CGRect {
        let margin = Constants.gap / 2
        return CGRect(
            x: frame.minX - margin,
            y: frame.minY - Constants.titleHeight - margin,
            width: frame.width + margin * 2,
            height: frame.height + Constants.titleHeight + margin * 2,
        )
    }
}
