import ArgumentParser
import Foundation
import RefraxProtocol

struct HistoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Browse and search history",
        subcommands: [
            List.self,
            Search.self,
            Clear.self,
            Frequent.self,
        ],
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List recent history",
            discussion: """
            Shows recently visited pages, optionally filtered by domain.
            
            Examples:
              refrax-ctl history list
              refrax-ctl history list --limit 10
              refrax-ctl history list --domain example.com
              refrax-ctl history list --json
            """,
        )

        @Option(name: .long, help: "Maximum number of entries")
        var limit: Int?

        @Option(name: .long, help: "Filter by domain")
        var domain: String?

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(
                .historyList(.init(limit: limit, domain: domain)),
                json: json,
            )
        }
    }

    struct Search: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "search",
            abstract: "Search history",
            discussion: """
            Searches history entries by title or URL.
            
            Examples:
              refrax-ctl history search "swift"
              refrax-ctl history search "documentation" --limit 5
              refrax-ctl history search "github" --json
            """,
        )

        @Argument(help: "Search query")
        var query: String

        @Option(name: .long, help: "Maximum number of results")
        var limit: Int?

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(
                .historySearch(.init(query: query, limit: limit)),
                json: json,
            )
        }
    }

    struct Clear: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "clear",
            abstract: "Clear browsing history",
            discussion: """
            Clears all browsing history, or only history for a specific domain.
            
            Examples:
              refrax-ctl history clear
              refrax-ctl history clear --domain example.com
            """,
        )

        @Option(name: .long, help: "Only clear history for this domain")
        var domain: String?

        func run() async throws {
            try sendAndHandle(.historyClear(.init(domain: domain)))
        }
    }

    struct Frequent: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "frequent",
            abstract: "Show frequently visited sites",
            discussion: """
            Lists the most frequently visited sites.
            
            Examples:
              refrax-ctl history frequent
              refrax-ctl history frequent --limit 10
              refrax-ctl history frequent --json
            """,
        )

        @Option(name: .long, help: "Maximum number of results")
        var limit: Int?

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(
                .historyFrequent(.init(limit: limit)),
                json: json,
            )
        }
    }
}
