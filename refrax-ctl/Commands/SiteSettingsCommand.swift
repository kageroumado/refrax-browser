import ArgumentParser
import Foundation
import RefraxProtocol

struct SiteSettingsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "site-settings",
        abstract: "Manage per-site settings",
        subcommands: [
            Get.self,
            Set.self,
        ],
    )

    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Get site settings for a domain",
            discussion: """
            Shows the per-site settings for the specified domain.
            
            Examples:
              refrax-ctl site-settings get example.com
              refrax-ctl site-settings get example.com --json
            """,
        )

        @Argument(help: "Domain to get settings for")
        var domain: String

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(
                .siteSettingsGet(.init(domain: domain)),
                json: json,
            )
        }
    }

    struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Modify site settings for a domain",
            discussion: """
            Sets per-site settings for the specified domain. Only the \
            options you provide will be changed.
            
            Examples:
              refrax-ctl site-settings set example.com --zoom 125
              refrax-ctl site-settings set example.com --js off
              refrax-ctl site-settings set example.com --blockers on --zoom 100
            """,
        )

        @Argument(help: "Domain to configure")
        var domain: String

        @Option(name: .long, help: "Zoom level percentage")
        var zoom: Int?

        @Option(name: .long, help: "JavaScript: on or off")
        var js: String?

        @Option(name: .long, help: "Content blockers: on or off")
        var blockers: String?

        func run() async throws {
            let jsEnabled: Bool? = js.flatMap {
                switch $0.lowercased() {
                case "on", "true", "yes", "1": true
                case "off", "false", "no", "0": false
                default: nil
                }
            }
            let blockersEnabled: Bool? = blockers.flatMap {
                switch $0.lowercased() {
                case "on", "true", "yes", "1": true
                case "off", "false", "no", "0": false
                default: nil
                }
            }

            try sendAndHandle(
                .siteSettingsSet(.init(
                    domain: domain,
                    zoom: zoom,
                    javascript: jsEnabled,
                    contentBlockers: blockersEnabled,
                )),
            )
        }
    }
}
