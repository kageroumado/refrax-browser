import Foundation
import Testing

@testable import Refrax

// MARK: - PopupContentProbe Tests

@Suite("PopupContentProbe", .tags(.navigation))
@MainActor
struct PopupContentProbeTests {
    // MARK: - Helper

    private func isSkipProbe(_ result: PopupContentProbe.ProbeResult) -> Bool {
        if case .skipProbe = result { return true }
        return false
    }

    // MARK: - Should Probe Decision

    @Test("Should probe PDF extension")
    func shouldProbePDF() async {
        let url = URL(string: "https://example.com/document.pdf")!
        let result = await PopupContentProbe.shared.probe(url, timeout: 0.1)

        // Without network, will return .unknown due to timeout, but the point is it DOES probe
        // (doesn't return .skipProbe)
        #expect(!isSkipProbe(result))
    }

    @Test("Should probe ZIP extension")
    func shouldProbeZIP() async {
        let url = URL(string: "https://example.com/archive.zip")!
        let result = await PopupContentProbe.shared.probe(url, timeout: 0.1)

        #expect(!isSkipProbe(result))
    }

    @Test("Should probe DMG extension")
    func shouldProbeDMG() async {
        let url = URL(string: "https://example.com/installer.dmg")!
        let result = await PopupContentProbe.shared.probe(url, timeout: 0.1)

        #expect(!isSkipProbe(result))
    }

    @Test("Should probe EXE extension")
    func shouldProbeEXE() async {
        let url = URL(string: "https://example.com/setup.exe")!
        let result = await PopupContentProbe.shared.probe(url, timeout: 0.1)

        #expect(!isSkipProbe(result))
    }

    @Test("Should probe MP4 extension")
    func shouldProbeMP4() async {
        let url = URL(string: "https://example.com/video.mp4")!
        let result = await PopupContentProbe.shared.probe(url, timeout: 0.1)

        #expect(!isSkipProbe(result))
    }

    @Test("Skip probe for URL without extension")
    func skipProbeNoExtension() async {
        let url = URL(string: "https://example.com/page")!
        let result = await PopupContentProbe.shared.probe(url, timeout: 0.1)

        #expect(isSkipProbe(result))
    }

    @Test("Skip probe for HTML extension")
    func skipProbeHTML() async {
        let url = URL(string: "https://example.com/page.html")!
        let result = await PopupContentProbe.shared.probe(url, timeout: 0.1)

        #expect(isSkipProbe(result))
    }

    @Test("Skip probe for PHP extension")
    func skipProbePHP() async {
        let url = URL(string: "https://example.com/page.php")!
        let result = await PopupContentProbe.shared.probe(url, timeout: 0.1)

        #expect(isSkipProbe(result))
    }

    @Test("Skip probe for ASPX extension")
    func skipProbeASPX() async {
        let url = URL(string: "https://example.com/page.aspx")!
        let result = await PopupContentProbe.shared.probe(url, timeout: 0.1)

        #expect(isSkipProbe(result))
    }

    @Test("Skip probe for JSP extension")
    func skipProbeJSP() async {
        let url = URL(string: "https://example.com/page.jsp")!
        let result = await PopupContentProbe.shared.probe(url, timeout: 0.1)

        #expect(isSkipProbe(result))
    }

    // MARK: - Extension Coverage

    @Test("Probes disk images")
    func probesDiskImages() async {
        let extensions = ["dmg", "iso", "img", "pkg"]
        for ext in extensions {
            let url = URL(string: "https://example.com/file.\(ext)")!
            let result = await PopupContentProbe.shared.probe(url, timeout: 0.1)
            #expect(!isSkipProbe(result), "Expected to probe .\(ext)")
        }
    }

    @Test("Probes archives")
    func probesArchives() async {
        let extensions = ["zip", "rar", "7z", "tar", "gz"]
        for ext in extensions {
            let url = URL(string: "https://example.com/file.\(ext)")!
            let result = await PopupContentProbe.shared.probe(url, timeout: 0.1)
            #expect(!isSkipProbe(result), "Expected to probe .\(ext)")
        }
    }

    @Test("Probes documents")
    func probesDocuments() async {
        let extensions = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx"]
        for ext in extensions {
            let url = URL(string: "https://example.com/file.\(ext)")!
            let result = await PopupContentProbe.shared.probe(url, timeout: 0.1)
            #expect(!isSkipProbe(result), "Expected to probe .\(ext)")
        }
    }

    // MARK: - ProbeResult Cases

    @Test("ProbeResult download contains URL and filename")
    func probeResultDownload() {
        let url = URL(string: "https://example.com/file.zip")!
        let result = PopupContentProbe.ProbeResult.download(url: url, suggestedFilename: "file.zip")

        if case let .download(resultURL, filename) = result {
            #expect(resultURL == url)
            #expect(filename == "file.zip")
        } else {
            Issue.record("Expected download result")
        }
    }

    @Test("ProbeResult webpage contains URL")
    func probeResultWebpage() {
        let url = URL(string: "https://example.com/page")!
        let result = PopupContentProbe.ProbeResult.webpage(url: url)

        if case let .webpage(resultURL) = result {
            #expect(resultURL == url)
        } else {
            Issue.record("Expected webpage result")
        }
    }

    @Test("ProbeResult enum cases exist")
    func probeResultCases() {
        // Just verify the enum cases compile
        _ = PopupContentProbe.ProbeResult.skipProbe
        _ = PopupContentProbe.ProbeResult.unknown
        _ = PopupContentProbe.ProbeResult.download(url: URL(string: "https://x.com")!, suggestedFilename: nil)
        _ = PopupContentProbe.ProbeResult.webpage(url: URL(string: "https://x.com")!)
    }

    // MARK: - Case Insensitivity

    @Test("Extension matching is case insensitive")
    func extensionCaseInsensitive() async {
        let urls = [
            URL(string: "https://example.com/file.PDF")!,
            URL(string: "https://example.com/file.Pdf")!,
            URL(string: "https://example.com/file.pDf")!,
        ]

        for url in urls {
            let result = await PopupContentProbe.shared.probe(url, timeout: 0.1)
            #expect(!isSkipProbe(result), "Expected to probe \(url.pathExtension)")
        }
    }
}
