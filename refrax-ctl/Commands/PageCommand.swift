import ArgumentParser
import Foundation
import RefraxProtocol

struct PageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "page",
        abstract: "Page-level operations",
        subcommands: [
            ZoomIn.self,
            ZoomOut.self,
            ZoomReset.self,
            Find.self,
            Exec.self,
            Source.self,
            FindNext.self,
            FindPrevious.self,
            FindDismiss.self,
            VideoViewer.self,
            Pip.self,
        ],
    )

    struct ZoomIn: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "zoom-in",
            abstract: "Zoom in on the page",
            discussion: """
            Increases the zoom level of the page.
            
            Examples:
              refrax-ctl page zoom-in
              refrax-ctl page zoom-in --tab ABC123
              refrax-ctl page zoom-in --page DEF456
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            try sendAndHandle(.pageZoomIn(.init(tabID: tab, pageID: page)))
        }
    }

    struct ZoomOut: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "zoom-out",
            abstract: "Zoom out on the page",
            discussion: """
            Decreases the zoom level of the page.
            
            Examples:
              refrax-ctl page zoom-out
              refrax-ctl page zoom-out --tab ABC123
              refrax-ctl page zoom-out --page DEF456
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            try sendAndHandle(.pageZoomOut(.init(tabID: tab, pageID: page)))
        }
    }

    struct ZoomReset: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "zoom-reset",
            abstract: "Reset page zoom to 100%",
            discussion: """
            Resets the page zoom level to the default (100%).
            
            Examples:
              refrax-ctl page zoom-reset
              refrax-ctl page zoom-reset --tab ABC123
              refrax-ctl page zoom-reset --page DEF456
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            try sendAndHandle(.pageZoomReset(.init(tabID: tab, pageID: page)))
        }
    }

    struct Find: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "find",
            abstract: "Find text on the page",
            discussion: """
            Searches for text on the current page, highlighting matches.
            
            Examples:
              refrax-ctl page find "search term"
              refrax-ctl page find "login" --tab ABC123
              refrax-ctl page find "login" --page DEF456
            """,
        )

        @Argument(help: "Text to search for")
        var query: String

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            try sendAndHandle(
                .pageFind(.init(query: query, tabID: tab, pageID: page)),
            )
        }
    }

    struct Exec: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "exec",
            abstract: "Execute JavaScript on the page",
            discussion: """
            Evaluates a JavaScript expression on the page and prints the result. \
            This is the most powerful command for agent workflows — it enables \
            arbitrary page manipulation.
            
            Examples:
              refrax-ctl page exec "document.title"
              refrax-ctl page exec "document.querySelectorAll('a').length"
              refrax-ctl page exec "document.body.style.background = 'red'"
              refrax-ctl page exec "JSON.stringify(performance.timing)" --tab ABC123
              refrax-ctl page exec "document.title" --page DEF456
            """,
        )

        @Argument(help: "JavaScript to evaluate")
        var script: String

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        @Flag(name: .long, help: "Evaluate without a synthesized user gesture (preserves the page's transient user activation; gesture-forced evaluation strips it)")
        var noGesture = false

        func run() async throws {
            let response = try ControlClient.send(
                .pageExecJS(.init(script: script, tabID: tab, pageID: page, noGesture: noGesture ? true : nil)),
            )
            switch response {
            case let .javascript(result):
                print(result)
            case let .error(info):
                printError("Error [\(info.code)]: \(info.message)")
                _Exit(1)
            default:
                handleResponse(response)
            }
        }
    }

    struct Source: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "source",
            abstract: "Get the page's HTML source",
            discussion: """
            Returns the full HTML source of the page.
            
            Examples:
              refrax-ctl page source
              refrax-ctl page source --tab ABC123
              refrax-ctl page source --page DEF456
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            try sendAndHandle(.pageSource(.init(tabID: tab, pageID: page)))
        }
    }

    struct VideoViewer: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "video-viewer",
            abstract: "Control the in-window video viewer (fullscreen inside the tab)",
            discussion: """
            Drives WebKit's in-window video viewer: the current video expands to \
            fill the web view while browser chrome stays visible, without creating \
            a macOS fullscreen space.

            Requires an active playback session — the video must have started \
            playing so it is registered as the page's playback-controls element; \
            without one, enter/exit/toggle are silent no-ops. The `canToggle` \
            status field is advisory (it can read false while enter still works); \
            `active` in the after-state is the authoritative signal.

            Examples:
              refrax-ctl page video-viewer status
              refrax-ctl page video-viewer enter
              refrax-ctl page video-viewer exit
              refrax-ctl page video-viewer toggle --tab 3
            """,
        )

        @Argument(help: "Action: enter, exit, toggle, or status")
        var action: String = "status"

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            guard let viewerAction = ControlRequest.PageVideoViewerParams.Action(rawValue: action) else {
                printError("Invalid action '\(action)'. Use: enter, exit, toggle, or status")
                _Exit(1)
            }
            try sendAndHandle(
                .pageVideoViewer(.init(action: viewerAction, tabID: tab, pageID: page)),
            )
        }
    }

    struct Pip: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "pip",
            abstract: "Control Picture-in-Picture for the current video",
            discussion: """
            Enters or exits the system Picture-in-Picture window for the page's \
            predominant video.

            Requires an active playback session — the video must have started \
            playing so it is registered as the page's playback-controls element; \
            without one, enter/exit/toggle are silent no-ops. `active` in the \
            after-state is the authoritative signal.

            Examples:
              refrax-ctl page pip status
              refrax-ctl page pip enter
              refrax-ctl page pip exit
              refrax-ctl page pip toggle --tab 3
            """,
        )

        @Argument(help: "Action: enter, exit, toggle, or status")
        var action: String = "status"

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            guard let pipAction = ControlRequest.PagePiPParams.Action(rawValue: action) else {
                printError("Invalid action '\(action)'. Use: enter, exit, toggle, or status")
                _Exit(1)
            }
            try sendAndHandle(
                .pagePiP(.init(action: pipAction, tabID: tab, pageID: page)),
            )
        }
    }

    // MARK: - Find Navigation

    struct FindNext: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "find-next",
            abstract: "Go to the next find match",
            discussion: """
            Advances to the next match from a previous find-in-page search.
            
            Examples:
              refrax-ctl page find-next
              refrax-ctl page find-next --tab 3
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            try sendAndHandle(.pageFindNext(.init(tabID: tab, pageID: page)))
        }
    }

    struct FindPrevious: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "find-previous",
            abstract: "Go to the previous find match",
            discussion: """
            Goes to the previous match from a previous find-in-page search.
            
            Examples:
              refrax-ctl page find-previous
              refrax-ctl page find-previous --tab 3
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            try sendAndHandle(.pageFindPrevious(.init(tabID: tab, pageID: page)))
        }
    }

    struct FindDismiss: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "find-dismiss",
            abstract: "Dismiss the find-in-page UI",
            discussion: """
            Closes the find-in-page overlay and clears highlights.
            
            Examples:
              refrax-ctl page find-dismiss
              refrax-ctl page find-dismiss --tab 3
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            try sendAndHandle(.pageFindDismiss(.init(tabID: tab, pageID: page)))
        }
    }
}
