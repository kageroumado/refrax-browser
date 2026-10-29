import Foundation
import Testing
@testable import Refrax

struct FileIslandTests {
    private let area = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)

    // MARK: - Default placement

    @Test
    func `default placement is the bottom corner opposite the Control Island`() {
        let left = FileIslandLayout.defaultPlacement(oppositeOf: ControlIslandPlacement(x: 0, y: 0.2))
        #expect(left == ControlIslandPlacement(x: 1, y: 1))

        let right = FileIslandLayout.defaultPlacement(oppositeOf: ControlIslandPlacement(x: 1, y: 0.5))
        #expect(right == ControlIslandPlacement(x: 0, y: 1))

        let centered = FileIslandLayout.defaultPlacement(oppositeOf: ControlIslandPlacement(x: 0.5, y: 0))
        #expect(centered == ControlIslandPlacement(x: 0, y: 1))
    }

    @Test
    func `default placement sits in the window's bottom right corner inside the margin`() {
        let height = FileIslandLayout.height(downloads: 1, shelf: 2, showsDropCell: false)
        let frame = FileIslandLayout.defaultPlacement(oppositeOf: ControlIslandPlacement()).railFrame(in: area, height: height)
        #expect(frame.maxX == area.maxX - ControlIslandPlacement.margin)
        #expect(frame.maxY == area.maxY - ControlIslandPlacement.margin)
        #expect(frame.width == ControlIslandPlacement.railWidth)
        #expect(frame.height == height)
    }

    @Test
    func `the default placement is already snapped`() {
        let placement = FileIslandLayout.defaultPlacement(oppositeOf: ControlIslandPlacement())
        let height = FileIslandLayout.height(downloads: 0, shelf: 3, showsDropCell: false)
        #expect(placement.snapped(in: area, height: height) == placement)
    }

    // MARK: - Snapping

    @Test
    func `a release near the bottom edge and a side snaps to the corner`() {
        let height = FileIslandLayout.height(downloads: 2, shelf: 0, showsDropCell: false)
        var placement = ControlIslandPlacement()
        let origin = CGPoint(
            x: area.maxX - ControlIslandPlacement.margin - ControlIslandPlacement.railWidth - 20,
            y: area.maxY - ControlIslandPlacement.margin - height - 20,
        )
        placement.move(to: origin, in: area, height: height)
        #expect(placement.snapped(in: area, height: height) == ControlIslandPlacement(x: 1, y: 1))
    }

    @Test
    func `a release near the middle of the bottom edge snaps to its center`() {
        let height = FileIslandLayout.height(downloads: 0, shelf: 1, showsDropCell: false)
        var placement = ControlIslandPlacement()
        placement.move(to: CGPoint(x: area.midX - 30, y: area.maxY - height - 20), in: area, height: height)
        #expect(placement.snapped(in: area, height: height) == ControlIslandPlacement(x: 0.5, y: 1))
    }

    @Test
    func `a release away from every edge stays where it was put`() {
        let height = FileIslandLayout.height(downloads: 1, shelf: 1, showsDropCell: false)
        var placement = ControlIslandPlacement()
        placement.move(to: CGPoint(x: 400, y: 300), in: area, height: height)
        #expect(placement.snapped(in: area, height: height) == placement)
    }

    // MARK: - Height

    @Test
    func `height counts cells, the drop cell, the divider, the overflow row, and the grip`() {
        let empty = FileIslandLayout.height(downloads: 0, shelf: 0, showsDropCell: false)
        #expect(isClose(empty, ControlIslandPlacement.contentInset + ControlIslandPlacement.rowHeight + FileIslandLayout.gripHeight))

        let cell = FileIslandLayout.cellSize
        #expect(isClose(FileIslandLayout.height(downloads: 0, shelf: 0, showsDropCell: true), empty + cell))
        #expect(isClose(FileIslandLayout.height(downloads: 2, shelf: 0, showsDropCell: false), empty + cell * 2))
        #expect(isClose(FileIslandLayout.height(downloads: 1, shelf: 2, showsDropCell: false), empty + cell * 3 + ControlIslandPlacement.sectionGap))
    }

    @Test
    func `a short window shows fewer cells`() {
        #expect(FileIslandLayout.visibleLimit(in: area, showsDropCell: false) == FileIslandLayout.maximumVisibleItems)
        let short = CGRect(x: 0, y: 0, width: 800, height: 200)
        let limit = FileIslandLayout.visibleLimit(in: short, showsDropCell: false)
        #expect(limit < FileIslandLayout.maximumVisibleItems)
        let height = FileIslandLayout.height(downloads: limit, shelf: 0, showsDropCell: false) + ControlIslandPlacement.sectionGap
        #expect(height <= short.height - ControlIslandPlacement.margin * 2)
    }

    // MARK: - Allocation

    @Test
    func `downloads take the first cells and the shelf the rest`() {
        let allocation = FileIslandAllocation(downloads: 2, shelf: 6, limit: 5)
        #expect(allocation.downloads == 2)
        #expect(allocation.shelf == 3)
        #expect(allocation.hidden == 3)
    }

    @Test
    func `many downloads leave no room for the shelf`() {
        let allocation = FileIslandAllocation(downloads: 7, shelf: 2, limit: 5)
        #expect(allocation.downloads == 5)
        #expect(allocation.shelf == 0)
        #expect(allocation.hidden == 4)
    }

    @Test
    func `everything fits with nothing hidden`() {
        let allocation = FileIslandAllocation(downloads: 1, shelf: 1, limit: 5)
        #expect(allocation.hidden == 0)
    }

    // MARK: - Recent downloads

    @Test
    func `a finished download stays for an hour`() {
        let now = Date()
        #expect(FileIslandLayout.isRecent(now.addingTimeInterval(-59 * 60), now: now))
        #expect(!FileIslandLayout.isRecent(now.addingTimeInterval(-61 * 60), now: now))
    }

    // MARK: - Hiding at the edge

    @Test @MainActor
    func `the island hides at the edge by default, and the setting survives relaunch`() throws {
        let suite = "FileIslandTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = ControlIslandConfiguration(defaults: defaults)
        #expect(configuration.fileIslandHidesAtEdge)
        #expect(!configuration.hidesAtEdge)
        configuration.setFileIslandHidesAtEdge(false)
        #expect(!ControlIslandConfiguration(defaults: defaults).fileIslandHidesAtEdge)
    }

    @Test @MainActor
    func `an idle island hides past its edge and the pointer at that edge brings it back`() {
        let state = FileIslandState()
        let island = CGRect(x: area.maxX - 8 - 36, y: 700, width: 36, height: 200)
        state.hitRegions = [island]
        state.hiddenEdge = .right
        state.revealStrip = ControlIslandPlacement.revealStrip(for: island, at: .right, in: area)
        #expect(!state.isHiddenAtEdge)

        state.tracksPointer(CGPoint(x: 200, y: 200))
        #expect(state.isHiddenAtEdge)

        state.hitRegions = []
        state.tracksPointer(CGPoint(x: area.maxX - 2, y: 800))
        #expect(!state.isHiddenAtEdge)
    }

    @Test @MainActor
    func `a download arriving brings a hidden island back`() {
        let state = FileIslandState()
        state.hiddenEdge = .left
        state.tracksPointer(CGPoint(x: 800, y: 500))
        #expect(state.isHiddenAtEdge)
        state.holdAwake(for: FileIslandState.arrivalHold)
        #expect(!state.isHiddenAtEdge)
    }

    @Test @MainActor
    func `an island away from the side edges never hides`() {
        let state = FileIslandState()
        state.tracksPointer(CGPoint(x: 800, y: 500))
        #expect(!state.isHiddenAtEdge)
        #expect(ControlIslandPlacement(x: 0.5, y: 1).horizontalEdge == nil)
    }

    // MARK: - Coupling under the rail

    private func rail(height: CGFloat, x: Double = 1) -> CGRect {
        ControlIslandPlacement(x: x, y: 0).railFrame(in: area, height: height)
    }

    @Test
    func `a coupled island sits a small gap under the rail, in its column`() {
        let rail = rail(height: 400)
        let fit = FileIslandCoupling.fit(below: rail, in: area, showsDropCell: false)
        #expect(fit == .full(limit: FileIslandLayout.maximumVisibleItems))
        let height = FileIslandLayout.height(downloads: 1, shelf: 2, showsDropCell: false)
        let frame = FileIslandCoupling.frame(for: fit, height: height, below: rail, in: area)
        #expect(frame.minY == rail.maxY + FileIslandCoupling.gap)
        #expect(frame.minX == rail.minX)
        #expect(frame.width == rail.width)
        #expect(!frame.intersects(rail))
    }

    @Test
    func `the coupled island follows the rail as it grows and never overlaps it`() {
        for railHeight in stride(from: CGFloat(200), through: 980, by: 26) {
            let rail = rail(height: railHeight)
            let fit = FileIslandCoupling.fit(below: rail, in: area, showsDropCell: false)
            let height: CGFloat = switch fit {
            case let .full(limit): FileIslandLayout.height(downloads: limit, shelf: 0, showsDropCell: false) + ControlIslandPlacement.sectionGap
            case .compact, .beside: FileIslandLayout.compactHeight
            }
            let frame = FileIslandCoupling.frame(for: fit, height: height, below: rail, in: area)
            #expect(!frame.intersects(rail), "rail \(railHeight): \(frame) overlaps \(rail)")
            #expect(frame.maxY <= area.maxY - ControlIslandPlacement.margin, "rail \(railHeight): \(frame) leaves the window")
            #expect(frame.minX >= area.minX + ControlIslandPlacement.margin)
        }
    }

    @Test
    func `a short window shows fewer files, then compacts, then puts the island beside the rail`() {
        let roomy = rail(height: 400)
        #expect(FileIslandCoupling.fit(below: roomy, in: area, showsDropCell: false) == .full(limit: 5))

        let fixed = FileIslandLayout.height(downloads: 0, shelf: 0, showsDropCell: false) + ControlIslandPlacement.sectionGap
        let twoCells = area.maxY - ControlIslandPlacement.margin - FileIslandCoupling.gap - fixed - FileIslandLayout.cellSize * 2
            - ControlIslandPlacement.margin - 1
        #expect(FileIslandCoupling.fit(below: rail(height: twoCells), in: area, showsDropCell: false) == .full(limit: 2))

        let compactRoom = area.height - ControlIslandPlacement.margin * 2 - FileIslandCoupling.gap - FileIslandLayout.compactHeight - 0.5
        let compact = rail(height: compactRoom)
        #expect(FileIslandCoupling.fit(below: compact, in: area, showsDropCell: false) == .compact)
        let compactFrame = FileIslandCoupling.frame(for: .compact, height: FileIslandLayout.compactHeight, below: compact, in: area)
        #expect(compactFrame.maxY <= area.maxY - ControlIslandPlacement.margin)
        #expect(!compactFrame.intersects(compact))

        let full = rail(height: area.height)
        #expect(FileIslandCoupling.fit(below: full, in: area, showsDropCell: false) == .beside)
        let beside = FileIslandCoupling.frame(for: .beside, height: FileIslandLayout.compactHeight, below: full, in: area)
        #expect(beside.maxX == full.minX - FileIslandCoupling.gap)
        #expect(beside.maxY == area.maxY - ControlIslandPlacement.margin)
        #expect(!beside.intersects(full))

        let leftRail = rail(height: area.height, x: 0)
        let leftBeside = FileIslandCoupling.frame(for: .beside, height: FileIslandLayout.compactHeight, below: leftRail, in: area)
        #expect(leftBeside.minX == leftRail.maxX + FileIslandCoupling.gap)
    }

    @Test
    func `the compact column is one cell and the grip`() {
        #expect(FileIslandLayout.compactHeight == ControlIslandPlacement.contentInset + FileIslandLayout.cellSize + FileIslandLayout.gripHeight)
        #expect(FileIslandLayout.compactHeight < FileIslandLayout.height(downloads: 1, shelf: 0, showsDropCell: false))
    }

    @Test
    func `an island dropped at the seam under the rail couples; one beside it only aligns`() {
        let rail = rail(height: 400)
        let height = FileIslandLayout.height(downloads: 0, shelf: 2, showsDropCell: false)
        let atSeam = CGRect(x: rail.minX - 6, y: rail.maxY + 20, width: rail.width, height: height)
        #expect(FileIslandCoupling.isAtSeam(atSeam, rail: rail))
        let overlapping = CGRect(x: rail.minX, y: rail.maxY - 12, width: rail.width, height: height)
        #expect(FileIslandCoupling.isAtSeam(overlapping, rail: rail))

        let lower = CGRect(x: rail.minX, y: rail.maxY + 80, width: rail.width, height: height)
        #expect(!FileIslandCoupling.isAtSeam(lower, rail: rail))
        let aside = CGRect(x: rail.minX - rail.width - 8, y: rail.maxY + 8, width: rail.width, height: height)
        #expect(!FileIslandCoupling.isAtSeam(aside, rail: rail))
        #expect(!FileIslandCoupling.isAtSeam(atSeam, rail: .zero))
    }

    @Test
    func `a coupled island resists a short pull, then pops free`() {
        let short = FileIslandCoupling.resistedOffset(for: CGSize(width: -20, height: 10))
        #expect(short == CGSize(width: -20 * FileIslandCoupling.resistance, height: 10 * FileIslandCoupling.resistance))
        #expect(FileIslandCoupling.resistedOffset(for: .zero) == .zero)
        #expect(FileIslandCoupling.resistedOffset(for: CGSize(width: 0, height: FileIslandCoupling.breakDistance)) == nil)
        #expect(FileIslandCoupling.resistedOffset(for: CGSize(width: -30, height: 30)) == nil)
    }

    @Test
    func `the seam glow sits in the gap under the rail`() {
        let rail = rail(height: 300)
        let seam = FileIslandCoupling.seamFrame(below: rail)
        #expect(seam.minY > rail.maxY)
        #expect(seam.maxY < rail.maxY + FileIslandCoupling.gap)
        #expect(seam.minX > rail.minX && seam.maxX < rail.maxX)
    }

    @Test @MainActor
    func `the pointer near a coupled island wakes the rail`() {
        let state = ControlIslandState(defaults: nil, configuration: ControlIslandConfiguration(defaults: nil))
        let rail = rail(height: 300)
        state.hitRegions = [rail]
        let island = CGRect(x: rail.minX, y: rail.maxY + FileIslandCoupling.gap, width: rail.width, height: 500)
        let nearIsland = CGPoint(x: rail.midX, y: island.maxY - 10)

        _ = state.tracksPointer(CGPoint(x: 100, y: 100))
        _ = state.tracksPointer(nearIsland)
        #expect(state.isQuiet)

        state.companionFrame = island
        _ = state.tracksPointer(nearIsland)
        #expect(!state.isQuiet)
    }

    private func isClose(_ a: CGFloat, _ b: CGFloat) -> Bool {
        abs(a - b) < 0.001
    }
}
