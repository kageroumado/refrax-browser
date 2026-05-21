import ArgumentParser
import Foundation

@main
struct RefraxCTL: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "refrax-ctl",
        abstract: "Control a running Refrax browser instance",
        discussion: """
        Global flags (place before the subcommand):
          -q, --quiet          Suppress success messages (errors still print to stderr)
          -v, --verbose        Print raw JSON request/response for debugging
          --timeout N          Set request timeout in seconds (default: 30)
          --retry N            Retry failed connections up to N times (default: 0)
          --retry-delay SECS   Delay between retries in seconds (default: 1.0)
          --version            Print CLI protocol version and exit
        
        Tab references (where a command accepts a tab argument):
          UUID                 Exact tab ID
          3                    Tab at index 3 (1-based, in current space)
          active               Currently active tab
          first / last         First or last tab in current space
          next / prev          Tab adjacent to active
          title:GitHub         Case-insensitive title match
          url:github.com       Case-insensitive URL match
          "Hacker News"        Fuzzy match on title or URL
        """,
        subcommands: [
            LaunchCommand.self,
            PingCommand.self,
            HealthCommand.self,
            StateCommand.self,
            FetchCommand.self,
            NavigateCommand.self,
            OpenCommand.self,
            ReadCommand.self,
            TabCommand.self,
            SpaceCommand.self,
            ScreenshotCommand.self,
            PageContentCommand.self,
            ClickCommand.self,
            FindElementsCommand.self,
            TypeCommand.self,
            ScrollCommand.self,
            HoverCommand.self,
            FormInputCommand.self,
            WaitCommand.self,
            PipeCommand.self,
            WindowCommand.self,
            RefPaneCommand.self,
            HotkeyCommand.self,
            UICommand.self,
            GroupCommand.self,
            PageCommand.self,
            BookmarkCommand.self,
            HistoryCommand.self,
            SiteSettingsCommand.self,
            SettingsCommand.self,
            DevCommand.self,
            VisualCommand.self,
            ExecCommand.self,
            DismissCookiesCommand.self,
        ],
    )

    /// Override the entry point to pre-parse global flags before
    /// ArgumentParser processes the remaining arguments.
    static func main() async {
        CLIConfig.parseGlobalFlags()
        do {
            var command = try parseAsRoot(CLIConfig.remainingArgs)
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exit(withError: error)
        }
    }
}
