import ArgumentParser
import Foundation
import RefraxProtocol

struct TabCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tab",
        abstract: "Manage browser tabs",
        subcommands: [
            List.self,
            Active.self,
            Open.self,
            Close.self,
            Activate.self,
            Navigate.self,
            Pin.self,
            Duplicate.self,
            Rename.self,
            Mute.self,
            Back.self,
            Forward.self,
            Next.self,
            Previous.self,
            Detail.self,
            CloseOthers.self,
            Reopen.self,
            RecentlyClosed.self,
            Move.self,
            Ungroup.self,
            ToRefPane.self,
            Reorder.self,
            MarkRead.self,
            MarkUnread.self,
            CopyURL.self,
            Reload.self,
            IsLoading.self,
            GetURL.self,
            WaitLoaded.self,
        ],
    )

    // MARK: - Existing Subcommands

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List tabs",
            discussion: """
            Lists all tabs, optionally filtered by space.
            
            Examples:
              refrax-ctl tab list
              refrax-ctl tab list --space ABC123
              refrax-ctl tab list --json
            """,
        )

        @Option(name: .long, help: "Filter by space ID")
        var space: String?

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(
                .tabList(.init(spaceID: space)),
                json: json,
            )
        }
    }

    struct Active: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show the active tab",
            discussion: """
            Displays information about the currently active tab.
            
            Examples:
              refrax-ctl tab active
              refrax-ctl tab active --json
            """,
        )

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            let response = try ControlClient.send(.state)
            if case let .state(info) = response {
                guard let activeTab = info.tabs.first(where: { $0.isActive }) else {
                    printError("No active tab")
                    _Exit(1)
                }
                if json {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let wrapped = ControlResponse.tab(activeTab)
                    if let data = try? encoder.encode(wrapped),
                       let str = String(data: data, encoding: .utf8) {
                        print(str)
                    }
                } else {
                    printTab(activeTab)
                }
            } else {
                handleResponse(response, json: json)
            }
        }
    }

    struct Open: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Open a new tab",
            discussion: """
            Opens a new tab with the specified URL.
            
            Examples:
              refrax-ctl tab open "https://example.com"
              refrax-ctl tab open "https://example.com" --activate
              refrax-ctl tab open "https://example.com" --space ABC123
            """,
        )

        @Argument(help: "URL to open")
        var url: String

        @Option(name: .long, help: "Space ID to open the tab in")
        var space: String?

        @Flag(name: .long, help: "Activate the new tab")
        var activate = false

        func run() async throws {
            try sendAndHandle(
                .tabOpen(.init(url: url, spaceID: space, activate: activate ? true : nil)),
            )
        }
    }

    struct Navigate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "navigate",
            abstract: "Navigate a tab to a URL",
            discussion: """
            Navigates the active (or specified) tab to a URL. Use --wait to block \
            until the page finishes loading, or --read to also return page content.

            Examples:
              refrax-ctl tab navigate "https://example.com"
              refrax-ctl tab navigate "https://example.com" --tab 3
              refrax-ctl tab navigate "https://example.com" --wait
              refrax-ctl tab navigate "https://example.com" --read --scope full
            """,
        )

        @Argument(help: "URL to navigate to")
        var url: String

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        @Flag(name: .long, help: "Wait for the page to finish loading")
        var wait = false

        @Flag(name: .long, help: "Return page content after navigation (implies --wait)")
        var read = false

        @Option(name: .long, help: "Content scope for --read (viewport/full/main/text/html)")
        var scope: String?

        @Option(name: .long, help: "Timeout in seconds for --wait/--read (default: 30)")
        var timeout: Int?

        func run() async throws {
            if read {
                var contentScope: ControlRequest.PageContentParams.Scope?
                if let scope {
                    let scopeValue = scope == "main" ? "mainContent" : scope
                    guard let parsed = ControlRequest.PageContentParams.Scope(rawValue: scopeValue) else {
                        printError("Invalid scope '\(scope)'. Use: viewport, full, main, html, or text")
                        _Exit(1)
                    }
                    contentScope = parsed
                }
                try sendAndHandle(
                    .navigateAndRead(.init(
                        url: url, scope: contentScope, timeout: timeout, tabID: tab, pageID: page
                    )),
                )
            } else if wait {
                try sendAndHandle(
                    .navigateAndWait(.init(url: url, tabID: tab, pageID: page, timeout: timeout)),
                )
            } else {
                try sendAndHandle(
                    .navigate(.init(url: url, tabID: tab, pageID: page)),
                )
            }
        }
    }

    struct Close: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Close a tab",
            discussion: """
            Closes the specified tab.

            Examples:
              refrax-ctl tab close 3             # By index
              refrax-ctl tab close active        # Active tab
              refrax-ctl tab close "Hacker News" # By title/URL match
            """,
        )

        @Argument(help: "Tab ref (ID, index, title, URL, or: active/first/last/next/prev)")
        var id: String

        func run() async throws {
            try sendAndHandle(.tabClose(.init(id: id)))
        }
    }

    struct Activate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Activate a tab",
            discussion: """
            Switches to the specified tab.
            
            Examples:
              refrax-ctl tab activate 3             # By index
              refrax-ctl tab activate last           # Last tab
              refrax-ctl tab activate "GitHub"       # By title/URL match
            """,
        )

        @Argument(help: "Tab ref (ID, index, title, URL, or: active/first/last/next/prev)")
        var id: String

        func run() async throws {
            try sendAndHandle(.tabActivate(.init(id: id)))
        }
    }

    // MARK: - Tier 1A: Extended Tab Operations

    struct Pin: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "pin",
            abstract: "Pin or unpin a tab",
            discussion: """
            Toggles the pin state of the specified tab. Pinned tabs stay at \
            the top of the sidebar.
            
            Examples:
              refrax-ctl tab pin 3             # By index
              refrax-ctl tab pin active        # Active tab
              refrax-ctl tab pin "Hacker News" # By title/URL match
            """,
        )

        @Argument(help: "Tab ref (ID, index, title, URL, or: active/first/last/next/prev)")
        var id: String

        func run() async throws {
            try sendAndHandle(.tabPin(.init(id: id)))
        }
    }

    struct Duplicate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "duplicate",
            abstract: "Duplicate a tab",
            discussion: """
            Creates a copy of the specified tab with the same URL.
            
            Examples:
              refrax-ctl tab duplicate 3             # By index
              refrax-ctl tab duplicate active        # Active tab
              refrax-ctl tab duplicate "Hacker News" # By title/URL match
            """,
        )

        @Argument(help: "Tab ref (ID, index, title, URL, or: active/first/last/next/prev)")
        var id: String

        func run() async throws {
            try sendAndHandle(.tabDuplicate(.init(id: id)))
        }
    }

    struct Rename: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "rename",
            abstract: "Set a custom name for a tab",
            discussion: """
            Sets a custom display name for the tab. Pass --clear to remove \
            the custom name and revert to the page title.
            
            Examples:
              refrax-ctl tab rename active "My Custom Name"
              refrax-ctl tab rename 3 "My Custom Name"
              refrax-ctl tab rename active --clear
            """,
        )

        @Argument(help: "Tab ref (ID, index, title, URL, or: active/first/last/next/prev)")
        var id: String

        @Argument(help: "Custom name for the tab")
        var name: String?

        @Flag(name: .long, help: "Clear the custom name")
        var clear = false

        func run() async throws {
            let nameValue = clear ? nil : name
            try sendAndHandle(.tabRename(.init(id: id, name: nameValue)))
        }
    }

    struct Mute: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "mute",
            abstract: "Toggle mute on a tab",
            discussion: """
            Toggles the audio mute state of the specified tab.
            
            Examples:
              refrax-ctl tab mute active        # Active tab
              refrax-ctl tab mute 3             # By index
              refrax-ctl tab mute "YouTube"     # By title/URL match
            """,
        )

        @Argument(help: "Tab ref (ID, index, title, URL, or: active/first/last/next/prev)")
        var id: String

        func run() async throws {
            try sendAndHandle(.tabMute(.init(id: id)))
        }
    }

    struct Back: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "back",
            abstract: "Navigate back in history",
            discussion: """
            Goes back one page in the tab's navigation history.
            
            Examples:
              refrax-ctl tab back
              refrax-ctl tab back --tab 3             # By index
              refrax-ctl tab back --tab "Hacker News" # By title/URL match
              refrax-ctl tab back --page DEF456
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            try sendAndHandle(.tabGoBack(.init(tabID: tab, pageID: page)))
        }
    }

    struct Forward: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "forward",
            abstract: "Navigate forward in history",
            discussion: """
            Goes forward one page in the tab's navigation history.
            
            Examples:
              refrax-ctl tab forward
              refrax-ctl tab forward --tab 3             # By index
              refrax-ctl tab forward --tab "Hacker News" # By title/URL match
              refrax-ctl tab forward --page DEF456
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            try sendAndHandle(.tabGoForward(.init(tabID: tab, pageID: page)))
        }
    }

    struct Next: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "next",
            abstract: "Switch to the next tab",
            discussion: """
            Activates the next tab in the tab list.
            
            Examples:
              refrax-ctl tab next
            """,
        )

        func run() async throws {
            try sendAndHandle(.tabNext)
        }
    }

    struct Previous: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "previous",
            abstract: "Switch to the previous tab",
            discussion: """
            Activates the previous tab in the tab list.
            
            Examples:
              refrax-ctl tab previous
            """,
        )

        func run() async throws {
            try sendAndHandle(.tabPrevious)
        }
    }

    struct Detail: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "detail",
            abstract: "Show detailed tab information",
            discussion: """
            Displays extended information about a tab, including navigation \
            state, group membership, pages, and more.
            
            Examples:
              refrax-ctl tab detail                    # Active tab
              refrax-ctl tab detail 3                  # By index
              refrax-ctl tab detail "Hacker News"      # By title/URL match
              refrax-ctl tab detail --page DEF456
              refrax-ctl tab detail --json
            """,
        )

        @Argument(help: "Tab ref (ID, index, title, URL, or: active/first/last/next/prev)")
        var id: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(.tabDetail(.init(tabID: id, pageID: page)), json: json)
        }
    }

    struct CloseOthers: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "close-others",
            abstract: "Close all tabs except the specified one",
            discussion: """
            Closes every tab in the current space except the one specified.
            
            Examples:
              refrax-ctl tab close-others active        # Keep active tab
              refrax-ctl tab close-others 3             # Keep tab at index 3
              refrax-ctl tab close-others "Hacker News" # Keep by title/URL match
            """,
        )

        @Argument(help: "Tab ref (ID, index, title, URL, or: active/first/last/next/prev)")
        var id: String

        func run() async throws {
            try sendAndHandle(.tabCloseOthers(.init(id: id)))
        }
    }

    struct Reopen: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "reopen",
            abstract: "Reopen the last closed tab",
            discussion: """
            Restores the most recently closed tab.
            
            Examples:
              refrax-ctl tab reopen
            """,
        )

        func run() async throws {
            try sendAndHandle(.tabReopenClosed)
        }
    }

    struct RecentlyClosed: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "recently-closed",
            abstract: "List recently closed tabs",
            discussion: """
            Shows tabs that were recently closed and can be reopened.
            
            Examples:
              refrax-ctl tab recently-closed
              refrax-ctl tab recently-closed --json
            """,
        )

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(.tabRecentlyClosed, json: json)
        }
    }

    struct Move: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "move",
            abstract: "Move a tab to a space or group",
            discussion: """
            Moves a tab to a different space or into a tab group. Specify \
            either --space or --group (not both).
            
            Examples:
              refrax-ctl tab move active --space SPACE_ID
              refrax-ctl tab move 3 --group GROUP_ID
              refrax-ctl tab move "Hacker News" --space SPACE_ID
            """,
        )

        @Argument(help: "Tab ref (ID, index, title, URL, or: active/first/last/next/prev)")
        var id: String

        @Option(name: .long, help: "Destination space ID")
        var space: String?

        @Option(name: .long, help: "Destination group ID")
        var group: String?

        func run() async throws {
            if let space {
                try sendAndHandle(.tabMoveToSpace(.init(id: id, spaceID: space)))
            } else if let group {
                try sendAndHandle(.tabMoveToGroup(.init(id: id, groupID: group)))
            } else {
                printError("Specify either --space or --group")
                _Exit(1)
            }
        }
    }

    struct Ungroup: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "ungroup",
            abstract: "Remove a tab from its group",
            discussion: """
            Removes the specified tab from whatever group it belongs to.
            
            Examples:
              refrax-ctl tab ungroup active        # Active tab
              refrax-ctl tab ungroup 3             # By index
              refrax-ctl tab ungroup "Hacker News" # By title/URL match
            """,
        )

        @Argument(help: "Tab ref (ID, index, title, URL, or: active/first/last/next/prev)")
        var id: String

        func run() async throws {
            try sendAndHandle(.tabRemoveFromGroup(.init(id: id)))
        }
    }

    struct ToRefPane: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "to-refpane",
            abstract: "Move a tab to the reference pane",
            discussion: """
            Moves the specified tab from the main area into the reference pane.
            
            Examples:
              refrax-ctl tab to-refpane active        # Active tab
              refrax-ctl tab to-refpane 3             # By index
              refrax-ctl tab to-refpane "Hacker News" # By title/URL match
            """,
        )

        @Argument(help: "Tab ref (ID, index, title, URL, or: active/first/last/next/prev)")
        var id: String

        func run() async throws {
            try sendAndHandle(.tabMoveToRefPane(.init(id: id)))
        }
    }

    struct Reorder: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "reorder",
            abstract: "Move a tab to a specific position",
            discussion: """
            Reorders a tab to the specified index in the tab list.
            
            Examples:
              refrax-ctl tab reorder active --index 0
              refrax-ctl tab reorder 3 --index 0
              refrax-ctl tab reorder "Hacker News" --index 5
            """,
        )

        @Argument(help: "Tab ref (ID, index, title, URL, or: active/first/last/next/prev)")
        var id: String

        @Option(name: .long, help: "Target index position")
        var index: Int

        func run() async throws {
            try sendAndHandle(.tabReorder(.init(id: id, index: index)))
        }
    }

    struct MarkRead: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "mark-read",
            abstract: "Mark a tab as read",
            discussion: """
            Marks the specified tab as read, removing the unread indicator.
            
            Examples:
              refrax-ctl tab mark-read active        # Active tab
              refrax-ctl tab mark-read 3             # By index
              refrax-ctl tab mark-read "Hacker News" # By title/URL match
            """,
        )

        @Argument(help: "Tab ref (ID, index, title, URL, or: active/first/last/next/prev)")
        var id: String

        func run() async throws {
            try sendAndHandle(.tabMarkRead(.init(id: id)))
        }
    }

    struct MarkUnread: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "mark-unread",
            abstract: "Mark a tab as unread",
            discussion: """
            Marks the specified tab as unread, showing the unread indicator.
            
            Examples:
              refrax-ctl tab mark-unread active        # Active tab
              refrax-ctl tab mark-unread 3             # By index
              refrax-ctl tab mark-unread "Hacker News" # By title/URL match
            """,
        )

        @Argument(help: "Tab ref (ID, index, title, URL, or: active/first/last/next/prev)")
        var id: String

        func run() async throws {
            try sendAndHandle(.tabMarkUnread(.init(id: id)))
        }
    }

    struct CopyURL: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "copy-url",
            abstract: "Print a tab's URL to stdout",
            discussion: """
            Outputs the tab's URL to stdout for piping. Use --markdown to \
            get a markdown link with the page title.
            
            Examples:
              refrax-ctl tab copy-url active             # Active tab
              refrax-ctl tab copy-url 3                  # By index
              refrax-ctl tab copy-url "Hacker News"      # By title/URL match
              refrax-ctl tab copy-url active --markdown
              refrax-ctl tab copy-url active | pbcopy
            """,
        )

        @Argument(help: "Tab ref (ID, index, title, URL, or: active/first/last/next/prev)")
        var id: String

        @Flag(name: .long, help: "Output as markdown link [title](url)")
        var markdown = false

        func run() async throws {
            let response = try ControlClient.send(
                .tabCopyURL(.init(id: id, markdown: markdown ? true : nil)),
            )
            switch response {
            case let .ok(message):
                if let message { print(message) }
            case let .error(info):
                printError("Error [\(info.code)]: \(info.message)")
                _Exit(1)
            default:
                handleResponse(response)
            }
        }
    }

    struct Reload: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "reload",
            abstract: "Reload a tab's page",
            discussion: """
            Reloads the current page. Use --from-origin to bypass cache.
            
            Examples:
              refrax-ctl tab reload
              refrax-ctl tab reload --tab 3             # By index
              refrax-ctl tab reload --tab "Hacker News" # By title/URL match
              refrax-ctl tab reload --from-origin
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        @Flag(name: .long, help: "Reload from origin, bypassing cache")
        var fromOrigin = false

        func run() async throws {
            let response = try ControlClient.send(
                .tabReload(.init(tabID: tab, pageID: page, fromOrigin: fromOrigin ? true : nil)),
            )
            handleResponse(response)
        }
    }

    // MARK: - Tab State Queries

    struct IsLoading: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "is-loading",
            abstract: "Check if a tab is loading",
            discussion: """
            Returns "true" or "false" indicating whether the tab is currently loading.
            
            Examples:
              refrax-ctl tab is-loading
              refrax-ctl tab is-loading --tab 3
              refrax-ctl tab is-loading --tab active
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            try sendAndHandle(.tabIsLoading(.init(tabID: tab, pageID: page)))
        }
    }

    struct GetURL: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "url",
            abstract: "Get the URL of a tab",
            discussion: """
            Returns the current URL of the tab's page.
            
            Examples:
              refrax-ctl tab url
              refrax-ctl tab url --tab 3
              refrax-ctl tab url --tab "Hacker News"
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            try sendAndHandle(.tabURL(.init(tabID: tab, pageID: page)))
        }
    }

    struct WaitLoaded: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "wait-loaded",
            abstract: "Wait until a tab finishes loading",
            discussion: """
            Blocks until the tab's page finishes loading, or until the timeout expires.
            
            Examples:
              refrax-ctl tab wait-loaded
              refrax-ctl tab wait-loaded --tab 3
              refrax-ctl tab wait-loaded --timeout 60
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        @Option(name: .long, help: "Timeout in seconds (default: 30)")
        var timeout: Int?

        func run() async throws {
            try sendAndHandle(.tabWaitLoaded(.init(tabID: tab, pageID: page, timeout: timeout)))
        }
    }
}
