import ArgumentParser
import Foundation
import RefraxProtocol

struct DevCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dev",
        abstract: "Developer tools",
        subcommands: [
            Inspector.self,
            Console.self,
            Resources.self,
            Profiling.self,
            ElementSelection.self,
            EmptyCaches.self,
            ConsoleLog.self,
            NetworkLog.self,
            Cookies.self,
            Storage.self,
        ],
    )

    // MARK: - Inspector Controls

    struct Inspector: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "inspector",
            abstract: "Toggle or control Web Inspector",
            discussion: """
            Opens/closes the Web Inspector, or controls its attachment state.
            
            Examples:
              refrax-ctl dev inspector
              refrax-ctl dev inspector --tab ABC123
              refrax-ctl dev inspector --page DEF456
              refrax-ctl dev inspector --attach --side bottom
              refrax-ctl dev inspector --detach
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        @Flag(name: .long, help: "Attach the inspector to the window")
        var attach = false

        @Flag(name: .long, help: "Detach the inspector to a separate window")
        var detach = false

        @Option(name: .long, help: "Attachment side: bottom or right")
        var side: String?

        func run() async throws {
            let action: String? = if attach {
                "attach"
            } else if detach {
                "detach"
            } else {
                nil
            }

            try sendAndHandle(
                .devInspector(.init(action: action, side: side, tabID: tab, pageID: page)),
            )
        }
    }

    struct Console: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "console",
            abstract: "Show the JavaScript console",
            discussion: """
            Opens the Web Inspector's JavaScript console panel.
            
            Examples:
              refrax-ctl dev console
              refrax-ctl dev console --tab ABC123
              refrax-ctl dev console --page DEF456
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            try sendAndHandle(.devConsole(.init(tabID: tab, pageID: page)))
        }
    }

    struct Resources: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "resources",
            abstract: "Show page resources",
            discussion: """
            Opens the Web Inspector's Resources panel.
            
            Examples:
              refrax-ctl dev resources
              refrax-ctl dev resources --tab ABC123
              refrax-ctl dev resources --page DEF456
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            try sendAndHandle(.devResources(.init(tabID: tab, pageID: page)))
        }
    }

    struct Profiling: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "profiling",
            abstract: "Toggle page profiling",
            discussion: """
            Toggles the Web Inspector's page profiling mode.
            
            Examples:
              refrax-ctl dev profiling
              refrax-ctl dev profiling --tab ABC123
              refrax-ctl dev profiling --page DEF456
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            try sendAndHandle(.devProfiling(.init(tabID: tab, pageID: page)))
        }
    }

    struct ElementSelection: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "element-selection",
            abstract: "Toggle element selection mode",
            discussion: """
            Toggles the Web Inspector's element selection (picker) mode.
            
            Examples:
              refrax-ctl dev element-selection
              refrax-ctl dev element-selection --tab ABC123
              refrax-ctl dev element-selection --page DEF456
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        func run() async throws {
            try sendAndHandle(.devElementSelection(.init(tabID: tab, pageID: page)))
        }
    }

    struct EmptyCaches: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "empty-caches",
            abstract: "Clear all web caches",
            discussion: """
            Empties all web content caches.
            
            Examples:
              refrax-ctl dev empty-caches
            """,
        )

        func run() async throws {
            try sendAndHandle(.devEmptyCaches)
        }
    }

    // MARK: - Programmatic Debugging

    struct ConsoleLog: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "console-log",
            abstract: "View captured console messages",
            discussion: """
            Returns buffered console.log/warn/error/info messages from the \
            page. Use --enable to install the capture hook, --clear to reset.
            
            Examples:
              refrax-ctl dev console-log
              refrax-ctl dev console-log --tab ABC123
              refrax-ctl dev console-log --page DEF456
              refrax-ctl dev console-log --enable
              refrax-ctl dev console-log --clear
              refrax-ctl dev console-log --json
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        @Flag(name: .long, help: "Enable console log capture")
        var enable = false

        @Flag(name: .long, help: "Clear the console log buffer")
        var clear = false

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            let action: String? = if enable {
                "enable"
            } else if clear {
                "clear"
            } else {
                nil
            }

            try sendAndHandle(
                .devConsoleLog(.init(action: action, tabID: tab, pageID: page)),
                json: json,
            )
        }
    }

    struct NetworkLog: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "network",
            abstract: "View captured network requests",
            discussion: """
            Returns buffered network request/response data from the page. \
            Use --clear to reset the buffer.
            
            Examples:
              refrax-ctl dev network
              refrax-ctl dev network --tab ABC123
              refrax-ctl dev network --page DEF456
              refrax-ctl dev network --clear
              refrax-ctl dev network --json
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        @Flag(name: .long, help: "Clear the network log buffer")
        var clear = false

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            let action: String? = clear ? "clear" : nil

            try sendAndHandle(
                .devNetworkLog(.init(action: action, tabID: tab, pageID: page)),
                json: json,
            )
        }
    }

    struct Cookies: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "cookies",
            abstract: "View page cookies",
            discussion: """
            Lists cookies for the current page, optionally filtered by domain.
            
            Examples:
              refrax-ctl dev cookies
              refrax-ctl dev cookies --domain example.com
              refrax-ctl dev cookies --tab ABC123
              refrax-ctl dev cookies --page DEF456
              refrax-ctl dev cookies --json
            """,
        )

        @Option(name: .long, help: "Filter by domain")
        var domain: String?

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(
                .devCookies(.init(domain: domain, tabID: tab, pageID: page)),
                json: json,
            )
        }
    }

    struct Storage: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "storage",
            abstract: "View or modify web storage",
            discussion: """
            Reads, writes, or deletes localStorage/sessionStorage entries. \
            Use --set to write, --delete to remove, or no flags to list.
            
            Examples:
              refrax-ctl dev storage
              refrax-ctl dev storage --session
              refrax-ctl dev storage --set key value
              refrax-ctl dev storage --delete key
              refrax-ctl dev storage --tab ABC123 --json
              refrax-ctl dev storage --page DEF456 --json
            """,
        )

        @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String?

        @Option(name: .long, help: "Page ID (for multi-page tabs)")
        var page: String?

        @Flag(name: .long, help: "Use sessionStorage (default: localStorage)")
        var session = false

        @Option(name: .long, help: "Set a storage key-value pair", transform: { $0 })
        var set: String?

        @Option(name: .long, help: "Value for --set")
        var value: String?

        @Option(name: .long, help: "Delete a storage key", transform: { $0 })
        var delete: String?

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            let storageType = session ? "session" : "local"

            if let key = set {
                try sendAndHandle(
                    .devStorage(.init(
                        action: "set",
                        storageType: storageType,
                        key: key,
                        value: value,
                        tabID: tab,
                        pageID: page,
                    )),
                )
            } else if let key = delete {
                try sendAndHandle(
                    .devStorage(.init(
                        action: "delete",
                        storageType: storageType,
                        key: key,
                        value: nil,
                        tabID: tab,
                        pageID: page,
                    )),
                )
            } else {
                try sendAndHandle(
                    .devStorage(.init(
                        action: nil,
                        storageType: storageType,
                        key: nil,
                        value: nil,
                        tabID: tab,
                        pageID: page,
                    )),
                    json: json,
                )
            }
        }
    }
}
