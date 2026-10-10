// Replays fixed drags against CanvasPhysics outside the app and prints how much of
// the desk each one disturbed. Run with Scripts/canvas-physics-bench/run.sh.
//
// "crowd" is the 60-tile Tab Canvas Lab grid, packed so tightly that any push must
// ripple outward; judge it by total displacement and falls. "sparse" has room
// everywhere; a drag through a tile there should move only the tiles in its path.

import CoreGraphics
import Foundation

let desk = CGRect(x: 0, y: 0, width: 4800, height: 3000)
let size = CGSize(width: 320, height: 200)
let dt: CGFloat = 1.0 / 60

var sparse = false
var verbose = false
func crowd() -> (CanvasPhysics, [UUID], [UUID: CGRect]) {
    if sparse {
        var world = CanvasPhysics(desk: desk)
        var ids: [UUID] = []
        var start: [UUID: CGRect] = [:]
        for i in 0 ..< 20 {
            let id = UUID()
            let f = CGRect(x: 120 + CGFloat(i % 5) * 900, y: 120 + CGFloat(i / 5) * 700, width: size.width, height: size.height)
            world.place(id, frame: f); ids.append(id); start[id] = f
        }
        return (world, ids, start)
    }
    var world = CanvasPhysics(desk: desk)
    var ids: [UUID] = []
    var start: [UUID: CGRect] = [:]
    for i in 0 ..< 60 {
        let id = UUID()
        let f = CGRect(x: 40 + CGFloat(i % 8) * 368, y: 40 + CGFloat(i / 8) * 272, width: size.width, height: size.height)
        world.place(id, frame: f); ids.append(id); start[id] = f
    }
    while world.isRunning { _ = world.step(dt) }
    return (world, ids, start)
}

func smooth(_ p: CGFloat) -> CGFloat { p * p * (3 - 2 * p) }

/// Drags tile `index` to `to` over `seconds`, releases, runs to rest; prints metrics.
func scenario(_ name: String, index: Int, to: CGPoint, seconds: CGFloat, fling: Bool) {
    var (world, ids, start) = crowd()
    let held = ids[index]
    let from = start[held]!
    var elapsed: CGFloat = 0
    var fell = 0
    while elapsed < seconds {
        elapsed = min(seconds, elapsed + dt)
        let p = elapsed / seconds
        let e = fling ? p * p : smooth(p)
        let f = CGRect(x: from.minX + (to.x - from.minX) * e, y: from.minY + (to.y - from.minY) * e, width: size.width, height: size.height)
        world.drag(held, to: f, elapsed: dt)
        for case let .fell(id) in world.step(dt) {
            fell += 1
            print("    fell while held: start", start[id]!.origin, "t", elapsed)
        }
    }
    let v = fling ? CGPoint(x: 2 * (to.x - from.minX) / seconds, y: 2 * (to.y - from.minY) / seconds) : .zero
    world.release(held, velocity: v, dropped: true)
    var settleTime: CGFloat = 0
    while world.isRunning, settleTime < 30 {
        for case let .fell(id) in world.step(dt) {
            fell += 1
            print("    fell after release: start", start[id]!.origin, "t", settleTime)
        }
        settleTime += dt
    }
    var moved: [CGFloat] = []
    for id in ids where id != held {
        guard let b = world.bodies[id] else { continue }
        let d = hypot(b.frame.minX - start[id]!.minX, b.frame.minY - start[id]!.minY)
        if d > 1 { moved.append(d); if verbose { print(String(format: "    %.0f,%.0f → %.0f,%.0f", start[id]!.minX, start[id]!.minY, b.frame.minX, b.frame.minY)) } }
    }
    moved.sort()
    let heldEnd = world.bodies[held]?.frame.origin ?? .zero
    let overl = overlaps(world)
    print(String(format: "%-8@ disturbed %2d  median %4.0f  max %4.0f  sum %6.0f  fell %d  settle %.2fs  held→%.0f,%.0f  overlaps %d",
                 name as NSString, moved.count, moved.isEmpty ? 0 : moved[moved.count / 2], moved.last ?? 0, moved.reduce(0, +), fell, settleTime, heldEnd.x, heldEnd.y, overl))
}

func overlaps(_ w: CanvasPhysics) -> Int {
    let boxes = w.bodies.values.map { CanvasPhysics.collisionBox($0.frame).insetBy(dx: CanvasPhysics.Constants.slop, dy: CanvasPhysics.Constants.slop) }
    var c = 0
    for i in boxes.indices { for j in (i + 1) ..< boxes.count where boxes[i].intersects(boxes[j]) { c += 1 } }
    return c
}

print("— crowd")
scenario("diag", index: 0, to: CGPoint(x: 1500, y: 800), seconds: 1.0, fling: false)
scenario("slow", index: 0, to: CGPoint(x: 1500, y: 800), seconds: 4.0, fling: false)
scenario("row", index: 24, to: CGPoint(x: 1200, y: 856), seconds: 1.0, fling: false)
scenario("fling", index: 0, to: CGPoint(x: 600, y: 40), seconds: 0.25, fling: true)

sparse = true
print("— sparse")
verbose = true
scenario("diag", index: 0, to: CGPoint(x: 2000, y: 1500), seconds: 1.0, fling: false)
scenario("row", index: 0, to: CGPoint(x: 2000, y: 120), seconds: 1.0, fling: false)
scenario("fling", index: 0, to: CGPoint(x: 700, y: 120), seconds: 0.2, fling: true)

/// Opens a space of `count` tabs laid out the way TabCanvasManager.placeUnplacedTabs
/// does, with nobody touching the desk, and reports what the settle did to it.
func opening(_ count: Int) {
    var world = CanvasPhysics(desk: desk)
    let step = CGSize(width: size.width + 48, height: size.height + 72)
    let columns = Int((desk.width - 240 + 48) / step.width)
    let rows = Int((desk.height - 240 + 48) / step.height)
    for index in 0 ..< count {
        let row = min(index / columns, rows - 1)
        world.place(UUID(), frame: CGRect(x: 120 + CGFloat(index % columns) * step.width, y: 120 + CGFloat(row) * step.height, width: size.width, height: size.height))
    }
    var fell = 0
    var elapsed: CGFloat = 0
    while world.isRunning, elapsed < 30 {
        fell += world.step(dt).count { if case .fell = $0 { true } else { false } }
        elapsed += dt
    }
    print(String(format: "open %3d  fell %3d  still moving %@  after %.1fs  overlaps %d", count, fell, world.isRunning ? "yes" : "no", elapsed, overlaps(world)))
}

print("— opening, untouched")
for count in [120, 150, 200] {
    opening(count)
}
