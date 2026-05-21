import ArgumentParser
import Foundation
import RefraxProtocol

struct WindowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "window",
        abstract: "Manage the browser window",
        subcommands: [
            Resize.self,
            Move.self,
            Center.self,
            Info.self,
            KeepOnTop.self,
            AllDesktops.self,
            LockSize.self,
            Opacity.self,
            FullScreen.self,
            Minimize.self,
        ],
    )

    // MARK: - Existing Subcommands

    struct Resize: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Resize the window",
            discussion: """
            Resizes the browser window to the specified dimensions.
            
            Examples:
              refrax-ctl window resize 1280x720
              refrax-ctl window resize 1920x1080
            """,
        )

        @Argument(help: "Size as WIDTHxHEIGHT (e.g. 1280x720)")
        var size: String

        func run() async throws {
            let parts = size.split(separator: "x")
            guard parts.count == 2,
                  let width = Int(parts[0]),
                  let height = Int(parts[1])
            else {
                printError("Invalid size '\(size)'. Use format: WIDTHxHEIGHT (e.g. 1280x720)")
                _Exit(1)
            }

            try sendAndHandle(
                .windowResize(.init(width: width, height: height)),
            )
        }
    }

    struct Move: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Move the window",
            discussion: """
            Moves the browser window to the specified screen position.
            
            Examples:
              refrax-ctl window move 100,100
              refrax-ctl window move 0,0
            """,
        )

        @Argument(help: "Position as X,Y (e.g. 100,100)")
        var position: String

        func run() async throws {
            let parts = position.split(separator: ",")
            guard parts.count == 2,
                  let x = Int(parts[0]),
                  let y = Int(parts[1])
            else {
                printError("Invalid position '\(position)'. Use format: X,Y (e.g. 100,100)")
                _Exit(1)
            }

            try sendAndHandle(
                .windowMove(.init(x: x, y: y)),
            )
        }
    }

    struct Center: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Center the window on screen",
            discussion: """
            Centers the browser window on the current screen.
            
            Examples:
              refrax-ctl window center
            """,
        )

        func run() async throws {
            try sendAndHandle(.windowCenter)
        }
    }

    struct Info: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Get window information",
            discussion: """
            Displays the window's position, size, and UI element states.
            
            Examples:
              refrax-ctl window info
              refrax-ctl window info --json
            """,
        )

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(.windowInfo, json: json)
        }
    }

    // MARK: - Tier 2D: Window Extended

    struct KeepOnTop: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "keep-on-top",
            abstract: "Toggle keep-on-top window level",
            discussion: """
            Toggles whether the window floats above other windows.
            
            Examples:
              refrax-ctl window keep-on-top
            """,
        )

        func run() async throws {
            try sendAndHandle(.windowKeepOnTop)
        }
    }

    struct AllDesktops: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "all-desktops",
            abstract: "Toggle visibility on all desktops",
            discussion: """
            Toggles whether the window appears on all virtual desktops/spaces.
            
            Examples:
              refrax-ctl window all-desktops
            """,
        )

        func run() async throws {
            try sendAndHandle(.windowAllDesktops)
        }
    }

    struct LockSize: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "lock-size",
            abstract: "Toggle window resize prevention",
            discussion: """
            Toggles whether the window can be resized by the user.
            
            Examples:
              refrax-ctl window lock-size
            """,
        )

        func run() async throws {
            try sendAndHandle(.windowLockSize)
        }
    }

    struct Opacity: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "opacity",
            abstract: "Set window opacity",
            discussion: """
            Sets the window transparency level as a percentage (0-100).
            
            Examples:
              refrax-ctl window opacity 100
              refrax-ctl window opacity 80
              refrax-ctl window opacity 60
            """,
        )

        @Argument(help: "Opacity percentage (0-100)")
        var percent: Int

        func run() async throws {
            try sendAndHandle(.windowSetOpacity(.init(percent: percent)))
        }
    }

    struct FullScreen: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "fullscreen",
            abstract: "Toggle full screen mode",
            discussion: """
            Toggles the window between full screen and windowed mode.
            
            Examples:
              refrax-ctl window fullscreen
            """,
        )

        func run() async throws {
            try sendAndHandle(.windowFullScreen)
        }
    }

    struct Minimize: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "minimize",
            abstract: "Minimize the window",
            discussion: """
            Minimizes the browser window to the Dock.
            
            Examples:
              refrax-ctl window minimize
            """,
        )

        func run() async throws {
            try sendAndHandle(.windowMinimize)
        }
    }
}
