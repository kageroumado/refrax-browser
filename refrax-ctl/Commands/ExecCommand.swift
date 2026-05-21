import ArgumentParser
import Foundation
import RefraxProtocol

struct ExecCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "exec",
        abstract: "Execute a browser automation program",
        discussion: """
        Runs a browser automation program. Programs can be provided inline, \
        read from a file, or piped via stdin.
        
        By default only `emit` output lines are printed. Use --verbose to see \
        step-by-step execution output.
        
        If the program uses `request_human`, execution pauses and you'll be \
        prompted to press Enter after performing the requested action.
        
        Examples:
          refrax-ctl exec 'emit "hello"'
          refrax-ctl exec --file program.txt
          echo 'emit "hello"' | refrax-ctl exec
          refrax-ctl exec --verbose --file workflow.txt
          refrax-ctl exec --dry-run --file workflow.txt
          refrax-ctl exec --timeout 120 --file long-task.txt
        """,
    )

    @Argument(help: "Program text (inline). Use --file or pipe from stdin for multi-line programs.")
    var program: String?

    @Option(name: .long, help: "Read program from file")
    var file: String?

    @Flag(name: .long, help: "Show step-by-step execution output")
    var verbose = false

    @Flag(name: .long, help: "Validate program without executing")
    var dryRun = false

    @Option(name: .long, help: "Maximum execution time in seconds")
    var timeout: Int = 60

    @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
    var tab: String?

    @Option(name: .long, help: "Page ID (for multi-page tabs)")
    var page: String?

    func run() async throws {
        let programText: String

        if let file {
            programText = try String(contentsOfFile: file, encoding: .utf8)
        } else if let program {
            programText = program
        } else {
            // Read from stdin
            var lines: [String] = []
            while let line = readLine(strippingNewline: false) {
                lines.append(line)
            }
            programText = lines.joined()
        }

        guard !programText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("No program provided. Pass inline, use --file, or pipe to stdin.")
        }

        try executeWithHumanLoop(programText: programText)
    }

    /// Executes the program, handling human intervention requests in a loop.
    ///
    /// When the server returns `.humanRequested`, this prints the description,
    /// waits for the user to press Enter, then sends `resumeProgram` to continue
    /// execution. The loop handles multiple consecutive human requests.
    private func executeWithHumanLoop(programText: String) throws {
        var response = try sendVerbose(.execProgram(.init(
            program: programText,
            timeout: timeout,
            verbose: verbose,
            dryRun: dryRun,
            tabID: tab,
            pageID: page,
        )))

        while case let .humanRequested(info) = response {
            printInfo("")
            printInfo("Agent needs help: \(info.description)")
            printInfo("Press Enter when done...")
            _ = readLine()
            response = try sendVerbose(.resumeProgram(.init(token: info.token)))
        }

        handleResponse(response)
    }

    private func sendVerbose(_ request: ControlRequest) throws -> ControlResponse {
        if CLIConfig.verbose {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(request),
               let str = String(data: data, encoding: .utf8) {
                printInfo("[request] \(str)")
            }
        }
        return try ControlClient.send(request)
    }
}
