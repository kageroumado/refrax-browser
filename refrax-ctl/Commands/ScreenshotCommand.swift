import ArgumentParser
import Foundation
import RefraxProtocol

struct ScreenshotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Take a screenshot of a tab or window",
    )

    @Argument(help: "Screenshot mode: window, visible, full, or window-glass")
    var mode: String = "visible"

    @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
    var tab: String?

    @Option(name: .long, help: "Page ID (for multi-page tabs)")
    var page: String?

    @Option(name: .long, help: "Output file path")
    var output: String = "/tmp/refrax-screenshot.png"

    @Flag(name: .long, help: "Draw coordinate grid overlay (in logical pixels)")
    var grid = false

    @Flag(name: .long, help: "Downscale to logical pixel dimensions")
    var logical = false

    @Option(name: .long, help: "Capture a page region as X,Y,W,H in document coordinates (overrides mode; use page exec getBoundingClientRect + scroll offsets to compute). Note: video layers render black in page captures — use window mode to verify video.")
    var rect: String?

    func run() async throws {
        guard let screenshotMode = ControlRequest.ScreenshotParams.ScreenshotMode(rawValue: mode) else {
            printError("Invalid mode '\(mode)'. Use: window, visible, full, or window-glass")
            _Exit(1)
        }

        let request = ControlRequest.screenshot(.init(
            mode: screenshotMode,
            tabID: tab,
            pageID: page,
            outputPath: output,
            grid: grid ? true : nil,
            logical: logical ? true : nil,
            rect: rect,
        ))

        let response = try ControlClient.send(request)

        switch response {
        case let .screenshot(info):
            guard let imageData = Data(base64Encoded: info.data) else {
                printError("Failed to decode screenshot data")
                _Exit(1)
            }
            let url = URL(fileURLWithPath: output)
            try imageData.write(to: url)
            print(output)
            if let pw = info.pixelWidth, let ph = info.pixelHeight, let sf = info.scaleFactor {
                print("Logical: \(info.width)x\(info.height), Pixel: \(pw)x\(ph), Scale: \(sf)x")
            }
        case let .error(info):
            printError("Error [\(info.code)]: \(info.message)")
            _Exit(1)
        default:
            handleResponse(response)
        }
    }
}
