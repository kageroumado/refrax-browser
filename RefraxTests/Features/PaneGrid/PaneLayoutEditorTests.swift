import Foundation
import Testing
@testable import Refrax

/// Layout mode as a state machine: entering, editing, and leaving, with the commit always
/// written to the tab the edit began on.
struct PaneLayoutEditorTests {
    private typealias Fixtures = PaneGridFixtures
    private let tabID = UUID()
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    /// A tab of two columns, stored as the grid stores it.
    private var columns: LayoutConfiguration? {
        PaneGrid(spans: [a: Fixtures.leftColumn, b: Fixtures.rightColumn]).configuration(columnSplit: 0.35, rowSplit: 0.5, activePaneID: a)
    }

    private func editing() -> PaneLayoutEditor {
        var editor = PaneLayoutEditor()
        editor.enter(tabID: tabID, configuration: columns, pageIDs: [a, b], activePageID: a)
        return editor
    }

    @Test
    func `Entering edits the tab's grid as stored, every cell covered`() throws {
        let editor = editing()
        let session = try #require(editor.session)
        #expect(editor.isEditing(tab: tabID))
        #expect(session.grid == PaneGrid(configuration: columns, pageIDs: [a, b]))
        #expect(session.grid.isComplete)
        #expect(session.columnSplit == 0.35)
    }

    @Test
    func `A second edit waits for the first to end`() {
        var editor = editing()
        let outcome = editor.enter(tabID: UUID(), configuration: nil, pageIDs: [UUID()], activePageID: nil)
        #expect(outcome == false)
        #expect(editor.isEditing(tab: tabID))
    }

    @Test
    func `Leaving without a change writes the layout back as it was`() throws {
        var editor = editing()
        let exited = editor.exit(pageIDs: [a, b])
        let commit = try #require(exited)
        #expect(commit.tabID == tabID)
        #expect(commit.configuration == columns)
        #expect(editor.isEditing == false)
    }

    @Test
    func `A move is committed to the tab the edit began on`() throws {
        var editor = editing()
        let outcome = editor.move(a, to: .topRight)
        #expect(outcome)
        let exited = editor.exit(pageIDs: [a, b])
        let commit = try #require(exited)
        #expect(commit.tabID == tabID)
        #expect(commit.positions == [a: .topRight, b: .topLeft])
        #expect(PaneGrid(configuration: commit.configuration, pageIDs: [a, b]).span(of: a) == Fixtures.rightColumn)
    }

    @Test
    func `Cells left empty by an edit are filled when it is committed`() throws {
        var editor = editing()
        let outcome = editor.shrink(a, from: .bottom)
        #expect(outcome)
        #expect(editor.session?.grid.emptyCells == [.bottomLeft])
        let exited = editor.exit(pageIDs: [a, b])
        let commit = try #require(exited)
        #expect(PaneGrid(configuration: commit.configuration, pageIDs: [a, b]).isComplete)
    }

    @Test
    func `The last pane stays`() {
        var editor = PaneLayoutEditor()
        editor.enter(tabID: tabID, configuration: nil, pageIDs: [a], activePageID: a)
        let outcome = editor.remove(a)
        #expect(outcome == false)
        #expect(editor.session?.grid.span(of: a) == .whole)
    }

    @Test
    func `A page joining the edited tab lands in the cell it was dropped on`() throws {
        var editor = editing()
        editor.shrink(a, from: .bottom)
        let outcome = editor.insert(c, joining: tabID, at: .cell(.bottomLeft))
        #expect(outcome)
        #expect(editor.session?.grid.span(of: c) == PaneSpan(.bottomLeft))
        let exited = editor.exit(pageIDs: [a, b, c])
        let commit = try #require(exited)
        #expect(commit.positions[c] == .bottomLeft)
    }

    @Test
    func `A page joining another tab leaves the edit alone`() {
        var editor = editing()
        let before = editor.session
        let outcome = editor.insert(c, joining: UUID(), at: .automatic)
        #expect(outcome == false)
        #expect(editor.session == before)
    }

    @Test
    func `Pages that left or joined the tab meanwhile are reconciled at the commit`() throws {
        var editor = editing()
        let exited = editor.exit(pageIDs: [a, c])
        let commit = try #require(exited)
        #expect(Set(commit.positions.keys) == [a, c])
        #expect(PaneGrid(configuration: commit.configuration, pageIDs: [a, c]).isComplete)
    }

    @Test
    func `A tab left with one page commits no layout`() throws {
        var editor = editing()
        let exited = editor.exit(pageIDs: [a])
        let commit = try #require(exited)
        #expect(commit.configuration == nil)
        #expect(commit.positions == [a: .single])
    }

    @Test
    func `Splits stay within their limits`() {
        var editor = editing()
        editor.setSplits(column: 0.95, row: 0.1)
        #expect(editor.session?.columnSplit == 0.8)
        #expect(editor.session?.rowSplit == 0.2)
    }

    @Test
    func `An edit whose tab is gone ends unwritten`() {
        var editor = editing()
        editor.discard()
        #expect(editor.isEditing == false)
        let outcome = editor.exit(pageIDs: [a, b])
        #expect(outcome == nil)
    }
}
