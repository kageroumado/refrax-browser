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
        static let slop: CGFloat = 0.25
        /// Time constant of a held body's measured speed: it is smoothed over pointer
        /// events and fades when the pointer stops, so a still hand pushes nothing.
        static let heldVelocityTimeConstant: CGFloat = 0.05
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
        return finish(touching: touching)
    }

    private mutating func integrate(_ dt: CGFloat) {
        let decay = exp(-Constants.friction * dt)
        let heldDecay = exp(-dt / Constants.heldVelocityTimeConstant)
        for (id, var body) in bodies where body.isHeld {
            body.velocity.x *= heldDecay
            body.velocity.y *= heldDecay
            bodies[id] = body
        }
        for (id, var body) in bodies where body.isAwake && !body.isHeld {
            body.frame.origin.x += body.velocity.x * dt
            body.frame.origin.y += body.velocity.y * dt
            body.velocity.x *= decay
            body.velocity.y *= decay
            if body.velocity != .zero {
                body.hasMoved = true
            }
            bodies[id] = body
        }
    }

    /// One pass of pairwise separation. Returns the bodies that touched something.
    private mutating func separate() -> Set<Tab.ID> {
        // Sweep along x: after sorting by the boxes' left edges, a body can only
        // overlap those that start before it ends.
        let order = bodies.map { (id: $0.key, box: Self.collisionBox($0.value.frame)) }
            .sorted { $0.box.minX < $1.box.minX }
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

    /// Pushes two overlapping bodies apart along the axis they overlap least on, and
    /// removes their closing speed along it. Returns false when they do not overlap.
    private func resolve(_ a: inout Body, _ b: inout Body) -> Bool {
        let boxA = Self.collisionBox(a.frame)
        let boxB = Self.collisionBox(b.frame)
        let overlapX = min(boxA.maxX, boxB.maxX) - max(boxA.minX, boxB.minX)
        let overlapY = min(boxA.maxY, boxB.maxY) - max(boxA.minY, boxB.minY)
        guard overlapX > Constants.slop, overlapY > Constants.slop else { return false }

        let inverseMassA: CGFloat = a.isHeld ? 0 : 1
        let inverseMassB: CGFloat = b.isHeld ? 0 : 1
        let totalInverseMass = inverseMassA + inverseMassB
        guard totalInverseMass > 0 else { return false }

        // Normal from a to b on the axis of least penetration. Coincident centers
        // break the tie toward +x so stacked tiles still come apart.
        let normal: CGPoint
        let depth: CGFloat
        if overlapX < overlapY {
            normal = CGPoint(x: boxB.midX >= boxA.midX ? 1 : -1, y: 0)
            depth = overlapX
        } else {
            normal = CGPoint(x: 0, y: boxB.midY >= boxA.midY ? 1 : -1)
            depth = overlapY
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

        Self.nudge(&a)
        Self.nudge(&b)
        return true
    }

    /// Wakes a body that was pushed, so it is simulated and reports where it rests.
    private static func nudge(_ body: inout Body) {
        guard !body.isHeld else { return }
        body.isAwake = true
        body.hasMoved = true
    }

    /// Drops bodies that left the desk and puts slow, untouched ones to rest.
    private mutating func finish(touching: Set<Tab.ID>) -> [Event] {
        var events: [Event] = []
        for (id, var body) in bodies where body.isAwake && !body.isHeld {
            if !desk.contains(CGPoint(x: body.frame.midX, y: body.frame.midY)) {
                bodies[id] = nil
                events.append(.fell(id))
                continue
            }
            guard !touching.contains(id), hypot(body.velocity.x, body.velocity.y) < Constants.restSpeed else { continue }
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
