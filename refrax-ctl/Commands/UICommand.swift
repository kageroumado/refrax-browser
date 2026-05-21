import ArgumentParser
import Foundation
import RefraxProtocol

struct UICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ui",
        abstract: "UI element controls and accessibility inspection",
        subcommands: [ToggleCommand.self, AXTreeCommand.self, AXClickCommand.self],
        defaultSubcommand: ToggleCommand.self,
    )
}

// MARK: - Toggle

extension UICommand {
    struct ToggleCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "toggle",
            abstract: "Toggle UI elements",
        )

        @Argument(help: "Element: sidebar, inspector, command-lens, or address-lens")
        var element: String

        func run() async throws {
            let request: ControlRequest
            switch element {
            case "sidebar": request = .sidebarToggle
            case "inspector": request = .inspectorToggle
            case "command-lens": request = .commandLens
            case "address-lens": request = .addressLens
            default:
                printError(
                    "Invalid element '\(element)'. Use: sidebar, inspector, command-lens, or address-lens",
                )
                _Exit(1)
            }

            try sendAndHandle(request)
        }
    }
}

// MARK: - Accessibility Tree

extension UICommand {
    struct AXTreeCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "ax-tree",
            abstract: "Dump the accessibility tree of the app window",
        )

        @Option(name: .long, help: "Maximum traversal depth")
        var depth: Int?

        @Option(name: .long, help: "Root at a specific accessibility identifier")
        var id: String?

        func run() async throws {
            let request = ControlRequest.uiAXTree(.init(depth: depth, id: id))
            try sendAndHandle(request)
        }
    }
}

// MARK: - Accessibility Click

extension UICommand {
    struct AXClickCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "ax-click",
            abstract: "Click a UI element by accessibility identifier",
        )

        @Argument(help: "Accessibility identifier of the element to click")
        var identifier: String

        func run() async throws {
            let request = ControlRequest.uiAXClick(.init(id: identifier))
            try sendAndHandle(request)
        }
    }
}
