import ArgumentParser
import Foundation
import RefraxProtocol

struct PipeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pipe",
        abstract: "Execute a sequence of commands from stdin",
        discussion: """
        Reads commands line-by-line from stdin and executes them sequentially. \
        Supports simple text format and raw JSON.
        
        Text format (one command per line):
          navigate URL
          wait SECONDS
          click REF | click X,Y
          hover REF | hover X,Y
          type TEXT
          scroll up|down|left|right [AMOUNT]
          scroll-to REF
          form-input REF VALUE
          screenshot [visible|full|window] [PATH]
          page-content [viewport|full|html|text]
          page-exec SCRIPT
        
        Lines starting with # are comments. Empty lines are skipped.
        Lines starting with { are parsed as raw JSON requests.
        
        Example:
          echo 'navigate https://example.com
          wait 2
          screenshot visible /tmp/test.png
          click e5' | refrax-ctl pipe
        
        Or from a file:
          refrax-ctl pipe < workflow.txt
        """,
    )

    @Flag(name: .long, help: "Print each command before executing")
    var verbose = false

    func run() async throws {
        var lineNum = 0
        while let line = readLine() {
            lineNum += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if verbose {
                printInfo("[\(lineNum)] \(trimmed)")
            }

            // Raw JSON
            if trimmed.hasPrefix("{") {
                guard let data = trimmed.data(using: .utf8) else {
                    printError("[\(lineNum)] Invalid UTF-8")
                    continue
                }
                do {
                    let request = try JSONDecoder().decode(ControlRequest.self, from: data)
                    try sendAndHandle(request)
                } catch {
                    printError("[\(lineNum)] \(error.localizedDescription)")
                }
                continue
            }

            // Text format
            do {
                try await executeLine(trimmed, lineNum: lineNum)
            } catch {
                printError("[\(lineNum)] \(error.localizedDescription)")
            }
        }
    }

    private func executeLine(_ line: String, lineNum: Int) async throws {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        guard let cmd = parts.first else { return }
        let args = parts.count > 1 ? parts[1] : ""

        switch cmd {
        case "wait":
            let seconds = Double(args) ?? 1.0
            guard seconds >= 0, seconds <= 30 else {
                printError("[\(lineNum)] Wait duration must be 0-30 seconds")
                return
            }
            if seconds > 0 {
                try await Task.sleep(for: .milliseconds(Int(seconds * 1_000)))
            }
            print("Waited \(seconds)s")

        case "navigate":
            try sendAndHandle(.navigate(.init(url: args)))

        case "click":
            if args.contains(","), !args.hasPrefix("e") {
                // Coordinate click: "100,200"
                let coordParts = args.split(separator: ",")
                if coordParts.count == 2, let x = Double(coordParts[0]), let y = Double(coordParts[1]) {
                    try sendAndHandle(.click(.init(x: x, y: y)))
                } else {
                    printError("[\(lineNum)] Invalid click coordinates: \(args)")
                }
            } else {
                try sendAndHandle(.click(.init(ref: args)))
            }

        case "hover":
            if args.contains(","), !args.hasPrefix("e") {
                let coordParts = args.split(separator: ",")
                if coordParts.count == 2, let x = Double(coordParts[0]), let y = Double(coordParts[1]) {
                    try sendAndHandle(.hover(.init(x: x, y: y)))
                } else {
                    printError("[\(lineNum)] Invalid hover coordinates: \(args)")
                }
            } else {
                try sendAndHandle(.hover(.init(ref: args)))
            }

        case "type":
            // Strip surrounding quotes if present
            var text = args
            if (text.hasPrefix("\"") && text.hasSuffix("\"")) || (text.hasPrefix("'") && text.hasSuffix("'")) {
                text = String(text.dropFirst().dropLast())
            }
            try sendAndHandle(.type(.init(text: text)))

        case "scroll":
            let scrollParts = args.split(separator: " ").map(String.init)
            let direction = scrollParts.first ?? "down"
            let amount = scrollParts.count > 1 ? Int(scrollParts[1]) : nil
            try sendAndHandle(.scroll(.init(direction: direction, amount: amount)))

        case "scroll-to":
            try sendAndHandle(.scroll(.init(ref: args)))

        case "form-input":
            let inputParts = args.split(separator: " ", maxSplits: 1).map(String.init)
            guard inputParts.count == 2 else {
                printError("[\(lineNum)] form-input requires REF and VALUE")
                return
            }
            var value = inputParts[1]
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            try sendAndHandle(.formInput(.init(ref: inputParts[0], value: value)))

        case "screenshot":
            let shotParts = args.split(separator: " ").map(String.init)
            let mode: ControlRequest.ScreenshotParams.ScreenshotMode = switch shotParts.first {
            case "full": .full
            case "window": .window
            default: .visible
            }
            let outputPath = shotParts.count > 1 ? shotParts.last : nil
            try sendAndHandle(.screenshot(.init(mode: mode, outputPath: outputPath)))

        case "page-content":
            let scope: ControlRequest.PageContentParams.Scope = switch args.trimmingCharacters(in: .whitespaces) {
            case "full": .full
            case "html": .html
            case "text": .text
            case "main": .mainContent
            default: .viewport
            }
            try sendAndHandle(.pageContent(.init(scope: scope)))

        case "page-exec":
            try sendAndHandle(.pageExecJS(.init(script: args)))

        case "ping":
            try sendAndHandle(.ping)

        case "state":
            try sendAndHandle(.state)

        default:
            printError("[\(lineNum)] Unknown command: \(cmd)")
        }
    }
}
