import ArgumentParser
import Foundation
import RefraxProtocol

/// The islands: the tabs of the front window's space as floating lists over the page.
struct IslandsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "islands",
        abstract: "Read and drive the tab islands",
        discussion: """
        Islands are the tab groups of the space, each a floating list over the page, plus one \
        for the tabs in no group. Rows reorder by drag, move between islands, join as panes, or \
        leave as live cards; these actions do the same from a script. Every action prints the \
        islands' state afterwards.
        
        Actions: state · show · hide · hold · release · step <up|down|left|right> · open --tab · \
        move-row --tab --island [--row N] · detach --tab [--to X,Y] · join --tab --with · \
        join-page --tab <left|right|up|down> [--pane P] · pin --island · unpin --island · \
        new-island --tab · move --island --to X,Y · icon-rail --island · titles --island
        
        Panes (the current tab's split view, a two-by-two grid): edit-panes · done-panes · \
        move-pane --pane P <top-left|top-right|bottom-left|bottom-right> · \
        grow-pane --pane P <left|right|up|down> · shrink-pane --pane P <left|right|up|down> · \
        separate-pane --pane P · splits --to COLUMN,ROW (shares of the page, 0.2–0.8). \
        move-pane, grow-pane and shrink-pane edit in layout mode (edit-panes); done-panes \
        stores the edit.
        
        An island is named by its id, a prefix of it, its title, or "tabs" for the loose tabs. \
        A tab is named as everywhere in refrax-ctl: an id, a prefix, or part of its title.
        """,
    )

    @Argument(help: "What to do; see the actions above")
    var action: String
    @Argument(help: "For step, join-page, grow-pane and shrink-pane: the direction; for move-pane: the cell")
    var direction: String?
    @Option(name: .long, help: "The tab the action is about")
    var tab: String?
    @Option(name: .long, help: "For join: the tab to join")
    var with: String?
    @Option(name: .long, help: "The island the action is about")
    var island: String?
    @Option(name: .long, help: "For move-row: the row the tab goes before; the end when left out")
    var row: Int?
    @Option(name: .long, help: "A point in window points: X,Y; for splits, the two shares")
    var to: String?
    @Option(name: .long, help: "A pane of the current tab: its page id or prefix, its index, or part of its title")
    var pane: String?
    @Flag(name: .long, help: "Output raw JSON")
    var json = false

    func run() async throws {
        guard let action = ControlRequest.IslandsParams.Action(rawValue: action) else {
            throw ValidationError("Unknown action '\(action)'; see --help for the list")
        }
        var x: Double?
        var y: Double?
        if let to {
            let parts = to.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2 else { throw ValidationError("--to takes X,Y in window points") }
            x = parts[0]
            y = parts[1]
        }
        let params = ControlRequest.IslandsParams(
            action: action, tab: tab, other: with, island: island, row: row, direction: direction, x: x, y: y, pane: pane,
        )
        try sendAndHandle(.islands(params), json: json)
    }
}
