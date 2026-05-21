import ArgumentParser
import Foundation
import RefraxProtocol

struct SettingsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "settings",
        abstract: "Manage global browser settings",
        subcommands: [
            List.self,
            Get.self,
            Set.self,
        ],
        defaultSubcommand: List.self,
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all settings with current values",
            discussion: """
            Shows all global browser settings grouped by category.
            
            Examples:
              refrax-ctl settings list
              refrax-ctl settings list --category appearance
              refrax-ctl settings list --json
            """,
        )

        @Option(name: .long, help: "Filter by category (general, appearance, tabs, privacy, advanced)")
        var category: String?

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(
                .settingsList(.init(category: category)),
                json: json,
            )
        }
    }

    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Get a setting's current value",
            discussion: """
            Shows the current value of a specific setting.
            
            Examples:
              refrax-ctl settings get webpageDarkMode
              refrax-ctl settings get enableJavaScript --json
            """,
        )

        @Argument(help: "Setting key (e.g., webpageDarkMode, enableJavaScript)")
        var key: String

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(
                .settingsGet(.init(key: key)),
                json: json,
            )
        }
    }

    struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Change a setting's value",
            discussion: """
            Sets a global browser setting. For toggle settings, use \
            on/off/toggle. For picker settings, use the value name.
            
            Examples:
              refrax-ctl settings set enableJavaScript on
              refrax-ctl settings set webpageDarkMode followSystem
              refrax-ctl settings set pageFilter sepia
              refrax-ctl settings set showTabPreviews toggle
            """,
        )

        @Argument(help: "Setting key (e.g., webpageDarkMode, enableJavaScript)")
        var key: String

        @Argument(help: "Value to set (on/off/toggle for booleans, value name for pickers)")
        var value: String

        func run() async throws {
            try sendAndHandle(
                .settingsSet(.init(key: key, value: value)),
            )
        }
    }
}
