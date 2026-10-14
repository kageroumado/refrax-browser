import CoreGraphics
import Foundation
import Testing
@testable import Refrax

struct TableCameraTests {
    private let camera = TableCamera(viewport: CGSize(width: 1_200, height: 800))
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()
    private let e = UUID()

    private func approx(_ lhs: Double, _ rhs: Double, within tolerance: Double = 1e-6) -> Bool {
        abs(lhs - rhs) < tolerance
    }

    private func approx(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        approx(lhs.minX, rhs.minX) && approx(lhs.minY, rhs.minY)
            && approx(lhs.width, rhs.width) && approx(lhs.height, rhs.height)
    }

    private func row(_ widths: [(UUID, TableWidth)], offset: Double = 0, focus: Int = 0) -> TableLayout.Row {
        TableLayout.Row(slabs: widths.map { TableLayout.Slab(tabID: $0.0, width: $0.1) }, offset: offset, focusedSlab: focus)
    }

    /// The viewpoint that shows `layout`'s current row at `offset` viewport widths.
    private func viewpoint(_ layout: TableLayout, row: Double? = nil, offset: Double) -> TableViewpoint {
        let rowIndex = row.map { Int($0.rounded()) } ?? layout.focusedRow
        let shift = CGFloat(offset - layout.rows[rowIndex].offset) * camera.viewport.width
        return TableViewpoint(row: row ?? Double(layout.focusedRow), shift: shift)
    }

    // MARK: - Frames

    @Test
    func `Slabs are their preset times the viewport width, full height, abutting`() {
        let layout = TableLayout(rows: [row([(a, .third), (b, .half), (c, .twoThirds), (d, .full)])])
        let frames = (0 ..< 4).map { camera.tableFrame(of: .init(row: 0, slab: $0), in: layout) }
        #expect(approx(frames[0].width, 400))
        #expect(approx(frames[1].width, 600))
        #expect(approx(frames[2].width, 800))
        #expect(approx(frames[3].width, 1_200))
        #expect(frames.allSatisfy { $0.height == 800 && $0.minY == 0 })
        for index in 1 ..< frames.count {
            #expect(approx(frames[index].minX, frames[index - 1].maxX))
        }
    }

    @Test
    func `Rows stack one viewport apart on the table`() {
        let layout = TableLayout(rows: [row([(a, .full)]), row([(b, .half)])])
        #expect(camera.tableFrame(of: .init(row: 1, slab: 0), in: layout).minY == 800)
    }

    // MARK: - What the viewport shows

    @Test
    func `At rest a full-width row shows its focused slab alone, live`() {
        let layout = TableLayout(tabIDs: [a, b, c]).movingFocus(.right)
        let visible = camera.visibleSlabs(in: layout, at: .resting(on: layout))
        #expect(visible.map(\.tabID) == [b])
        #expect(visible[0].frame == CGRect(x: 0, y: 0, width: 1_200, height: 800))
        #expect(visible[0].isWhole)
        #expect(camera.liveSlabs(in: layout) == [.init(row: 0, slab: 1)])
    }

    @Test
    func `Two half slabs in view are a live split`() {
        let layout = TableLayout(rows: [row([(a, .half), (b, .half), (c, .half)])])
        let visible = camera.visibleSlabs(in: layout, at: .resting(on: layout))
        #expect(visible.map(\.tabID) == [a, b])
        #expect(visible.allSatisfy(\.isWhole))
        #expect(camera.liveSlabs(in: layout).count == 2)
    }

    @Test
    func `A slab cut by the viewport's edge is visible but stays a snapshot`() {
        let layout = TableLayout(rows: [row([(a, .twoThirds), (b, .twoThirds)])])
        let visible = camera.visibleSlabs(in: layout, at: .resting(on: layout))
        #expect(visible.map(\.tabID) == [a, b])
        #expect(visible[0].isWhole)
        #expect(!visible[1].isWhole)
        #expect(camera.liveSlabs(in: layout) == [.init(row: 0, slab: 0)])
    }

    @Test
    func `Between rows both show, each at its own offset`() {
        let layout = TableLayout(rows: [
            row([(a, .full), (b, .full)], offset: 1, focus: 1),
            row([(c, .full), (d, .full)]),
        ])
        let visible = camera.visibleSlabs(in: layout, at: TableViewpoint(row: 0.25))
        #expect(visible.map(\.tabID) == [b, c])
        #expect(approx(visible[0].frame.minY, -200))
        #expect(approx(visible[1].frame.minY, 600))
        #expect(visible[0].frame.minX == 0)
        #expect(visible[1].frame.minX == 0)
        #expect(visible.allSatisfy { !$0.isWhole })
    }

    @Test
    func `A shift slides every row together`() throws {
        let layout = TableLayout(rows: [row([(a, .full), (b, .full)]), row([(c, .full), (d, .full)])])
        let visible = camera.visibleSlabs(in: layout, at: TableViewpoint(row: 0.5, shift: 300))
        #expect(Set(visible.map(\.tabID)) == [a, b, c, d])
        let frameA = try #require(visible.first { $0.tabID == a }?.frame)
        let frameC = try #require(visible.first { $0.tabID == c }?.frame)
        #expect(frameA.minX == -300)
        #expect(frameC.minX == -300)
    }

    // MARK: - Panning

    @Test
    func `A pan follows the fingers and stays on the table`() {
        let layout = TableLayout(rows: [row([(a, .full), (b, .full)]), row([(c, .full)])])
        let start = TableViewpoint.resting(on: layout)
        let left = camera.panned(start, by: CGSize(width: -300, height: 0), in: layout)
        #expect(left.shift == 300)
        let pastStart = camera.panned(start, by: CGSize(width: 500, height: 0), in: layout)
        #expect(pastStart.shift == 0)
        let pastEnd = camera.panned(start, by: CGSize(width: -5_000, height: 0), in: layout)
        #expect(pastEnd.shift == 1_200)
        let down = camera.panned(start, by: CGSize(width: 0, height: -400), in: layout)
        #expect(approx(down.row, 0.5))
        let pastBottom = camera.panned(start, by: CGSize(width: 0, height: -4_000), in: layout)
        #expect(pastBottom.row == 1)
        let pastTop = camera.panned(start, by: CGSize(width: 0, height: 400), in: layout)
        #expect(pastTop.row == 0)
    }

    // MARK: - Resting

    @Test
    func `A pan rests on the nearest row, then makes the slab nearest center whole`() throws {
        let layout = TableLayout(rows: [
            row([(a, .full), (b, .full)]),
            row([(c, .full), (d, .full), (e, .full)], offset: 1, focus: 1),
        ])
        let diagonal = TableViewpoint(row: 0.7, shift: 1_200 * 0.8)
        let rest = try #require(camera.restingTarget(in: layout, from: diagonal))
        #expect(rest.row == 1)
        #expect(approx(rest.offset, 2))
        #expect(rest.focusedSlab == 2)
    }

    @Test
    func `A slab that fits beside its neighbor keeps the neighbor in view`() throws {
        let layout = TableLayout(rows: [row([(a, .half), (b, .half), (c, .half), (d, .half)])])
        let rest = try #require(camera.restingTarget(in: layout, from: viewpoint(layout, offset: 0.6)))
        #expect(approx(rest.offset, 0.5))
        #expect(rest.focusedSlab == 2)
        let settled = layout.resting(at: rest)
        #expect(Set(camera.liveSlabs(in: settled).map(\.slab)) == [1, 2])
    }

    @Test
    func `A slab too wide to share the view is centered`() throws {
        let layout = TableLayout(rows: [row([(a, .twoThirds), (b, .twoThirds), (c, .twoThirds)])])
        let rest = try #require(camera.restingTarget(in: layout, from: viewpoint(layout, offset: 0.45)))
        #expect(approx(rest.offset, 0.5))
        #expect(rest.focusedSlab == 1)
        let settled = layout.resting(at: rest)
        let frame = try #require(camera.visibleSlabs(in: settled, at: .resting(on: settled)).first { $0.tabID == b }?.frame)
        #expect(approx(frame.midX, 600))
    }

    @Test
    func `A slab already whole beside a whole neighbor moves the view no further`() throws {
        let layout = TableLayout(rows: [row([(a, .third), (b, .third), (c, .third), (d, .third), (e, .third)])])
        let rest = try #require(camera.restingTarget(in: layout, from: viewpoint(layout, offset: 0.4)))
        #expect(approx(rest.offset, 0.4))
        #expect(rest.focusedSlab == 2)
        let row = layout.rows[0]
        #expect(row.isWhole(2, at: rest.offset))
        #expect(row.isWhole(3, at: rest.offset))
    }

    @Test
    func `The remembered slab stays current when it is still whole at rest`() throws {
        let layout = TableLayout(rows: [row([(a, .half), (b, .half), (c, .half), (d, .half)], offset: 0.5, focus: 1)])
        let rest = try #require(camera.restingTarget(in: layout, from: viewpoint(layout, offset: 0.55)))
        #expect(approx(rest.offset, 0.5))
        #expect(rest.focusedSlab == 1)
    }

    @Test
    func `Full-width slabs snap to the nearest one`() throws {
        let layout = TableLayout(tabIDs: [a, b, c])
        let forward = try #require(camera.restingTarget(in: layout, from: viewpoint(layout, offset: 0.6)))
        #expect(forward.offset == 1)
        #expect(forward.focusedSlab == 1)
        let back = try #require(camera.restingTarget(in: layout, from: viewpoint(layout, offset: 0.4)))
        #expect(back.offset == 0)
        #expect(back.focusedSlab == 0)
    }

    @Test
    func `A row shorter than the viewport rests left-aligned`() throws {
        let layout = TableLayout(rows: [row([(a, .third), (b, .third)])])
        let rest = try #require(camera.restingTarget(in: layout, from: TableViewpoint(row: 0, shift: 200)))
        #expect(rest.offset == 0)
    }

    @Test
    func `An empty table has no resting target`() {
        #expect(camera.restingTarget(in: TableLayout(), from: TableViewpoint(row: 0)) == nil)
        #expect(camera.visibleSlabs(in: TableLayout(), at: TableViewpoint(row: 0)).isEmpty)
    }

    @Test
    func `The rest's viewpoint shows what the settled layout shows`() throws {
        let layout = TableLayout(rows: [row([(a, .half), (b, .half), (c, .half), (d, .half)]), row([(e, .full)])])
        let rest = try #require(camera.restingTarget(in: layout, from: viewpoint(layout, row: 0.2, offset: 0.7)))
        let target = camera.viewpoint(for: rest, in: layout)
        let settled = layout.resting(at: rest)
        let before = camera.visibleSlabs(in: layout, at: target)
        let after = camera.visibleSlabs(in: settled, at: .resting(on: settled))
        #expect(before.map(\.tabID) == after.map(\.tabID))
        for (lhs, rhs) in zip(before, after) {
            #expect(approx(lhs.frame, rhs.frame))
        }
    }

    // MARK: - Focus moves and edits

    @Test
    func `The reveal for a focus move is the least offset change`() {
        let layout = TableLayout(rows: [row([(a, .third), (b, .third), (c, .third), (d, .third), (e, .third)])])
        #expect(camera.revealDelta(for: .init(row: 0, slab: 2), in: layout) == 0)
        #expect(approx(camera.revealDelta(for: .init(row: 0, slab: 3), in: layout), 1.0 / 3.0))
        #expect(approx(camera.revealDelta(for: .init(row: 0, slab: 4), in: layout), 2.0 / 3.0))
    }

    @Test
    func `An edit animates from the view the old layout showed`() {
        let old = TableLayout(tabIDs: [a, b, c])
        let new = old.inserting(d)
        let start = camera.transition(from: old, to: new)
        #expect(start.shift == -1_200)
        let before = camera.visibleSlabs(in: old, at: .resting(on: old))
        let during = camera.visibleSlabs(in: new, at: start)
        #expect(before.map(\.tabID) == during.map(\.tabID))
        #expect(approx(before[0].frame, during[0].frame))
    }

    @Test
    func `An edit that closes the current row animates from the new current row`() {
        let old = TableLayout(rows: [row([(a, .full)]), row([(b, .full)])])
        let new = old.removing(a)
        #expect(camera.transition(from: old, to: new) == .resting(on: new))
    }

    @Test
    func `A row followed across an edit above it keeps its view`() {
        let old = TableLayout(rows: [row([(a, .full)]), row([(b, .full), (c, .full)], offset: 1, focus: 1)], focusedRow: 1)
        let new = old.removing(a)
        let start = camera.transition(from: old, to: new)
        #expect(start == TableViewpoint(row: 0, shift: 0))
    }

    // MARK: - Wheel queue

    @Test
    func `Wheel notches queue and resolve to the slab they lead to`() {
        let layout = TableLayout(tabIDs: [a, b, c, d, e])
        var queue = TableStepQueue()
        for _ in 0 ..< 3 {
            queue.push(.right, from: layout)
        }
        #expect(queue.pending.count == 3)
        #expect(queue.resolved(from: layout).focusedTabID == d)
        #expect(queue.next() == .right)
        #expect(queue.pending.count == 2)
    }

    @Test
    func `Notches past the end of the row are dropped`() {
        let layout = TableLayout(tabIDs: [a, b])
        var queue = TableStepQueue()
        for _ in 0 ..< 5 {
            queue.push(.right, from: layout)
        }
        #expect(queue.pending == [.right])
        queue.push(.up, from: layout)
        #expect(queue.pending == [.right])
    }

    @Test
    func `A notch the other way cancels the last pending one`() {
        let layout = TableLayout(tabIDs: [a, b, c])
        var queue = TableStepQueue()
        queue.push(.right, from: layout)
        queue.push(.right, from: layout)
        queue.push(.left, from: layout)
        #expect(queue.pending == [.right])
        #expect(queue.resolved(from: layout).focusedTabID == b)
    }

    @Test
    func `Vertical notches step rows and keep each row's slab`() {
        let layout = TableLayout(rows: [row([(a, .full)]), row([(b, .full), (c, .full)], offset: 1, focus: 1), row([(d, .full)])])
        var queue = TableStepQueue()
        queue.push(.down, from: layout)
        queue.push(.down, from: layout)
        queue.push(.down, from: layout)
        #expect(queue.pending == [.down, .down])
        #expect(queue.resolved(from: layout).focusedTabID == d)
        var applied = layout
        while let step = queue.next() {
            applied = applied.movingFocus(step)
            if step == .down, applied.focusedRow == 1 {
                #expect(applied.focusedTabID == c)
            }
        }
        #expect(applied.focusedTabID == d)
        #expect(queue.isEmpty)
    }

    @Test
    func `Each queued slab passes in about 120 ms`() {
        #expect(TableStepQueue.stepInterval == 0.12)
    }

    // MARK: - Spring

    @Test
    func `The spring is critically damped with a 0.3 s response`() {
        #expect(TableSpring.response == 0.3)
        #expect(TableSpring.dampingFraction == 1)
    }

    @Test
    func `The spring starts at the start with the given velocity and ends at the target`() {
        #expect(TableSpring.value(from: 0, to: 100, at: 0) == 0)
        #expect(approx(TableSpring.velocity(from: 0, to: 100, velocity: 250, at: 0), 250))
        #expect(approx(TableSpring.value(from: 0, to: 100, at: 2), 100, within: 1e-3))
    }

    @Test
    func `The spring approaches without overshooting`() {
        var previous = 0.0
        for step in 1 ... 200 {
            let value = TableSpring.value(from: 0, to: 100, at: Double(step) * 0.005)
            #expect(value >= previous - 1e-9)
            #expect(value <= 100 + 1e-9)
            previous = value
        }
    }

    @Test
    func `Interpolating a viewpoint springs both axes`() {
        let start = TableViewpoint(row: 0, shift: 0)
        let target = TableViewpoint(row: 1, shift: -600)
        #expect(TableSpring.interpolate(from: start, to: target, elapsed: 0) == start)
        let middle = TableSpring.interpolate(from: start, to: target, elapsed: 0.1)
        #expect(middle.row > 0 && middle.row < 1)
        #expect(middle.shift < 0 && middle.shift > -600)
        let end = TableSpring.interpolate(from: start, to: target, elapsed: 3)
        #expect(approx(end.row, 1, within: 1e-4))
        #expect(approx(Double(end.shift), -600, within: 1e-2))
    }

    @Test
    func `The spring settles within a second and not at its start`() {
        let start = TableViewpoint(row: 0, shift: 0)
        let target = TableViewpoint(row: 1, shift: -1_200)
        #expect(!TableSpring.isSettled(from: start, to: target, elapsed: 0, rowHeight: 800))
        #expect(!TableSpring.isSettled(from: start, to: target, elapsed: 0.15, rowHeight: 800))
        #expect(TableSpring.isSettled(from: start, to: target, elapsed: 1, rowHeight: 800))
    }
}
