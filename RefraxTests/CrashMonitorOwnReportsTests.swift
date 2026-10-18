import Foundation
import Testing
@testable import Refrax

@Suite("Crash reports from this build")
struct CrashMonitorOwnReportsTests {
    private let release = "website.refrax.browser"

    private func report(bundleID: String?, procPath: String) throws -> URL {
        var header: [String: Any] = ["bug_type": "309", "app_name": "Refrax"]
        header["bundleID"] = bundleID
        let headerData = try JSONSerialization.data(withJSONObject: header)
        let bodyData = try JSONSerialization.data(withJSONObject: ["procPath": procPath])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Refrax-\(UUID().uuidString).ips")
        try (headerData + Data("\n".utf8) + bodyData).write(to: url)
        return url
    }

    @Test
    func `The installed app's crash is ours`() throws {
        let url = try report(bundleID: release, procPath: "/Applications/Refrax.app/Contents/MacOS/Refrax")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CrashMonitor.isFromThisBuild(url, bundleID: release))
    }

    @Test
    func `A debug build's crash belongs to the debug build`() throws {
        let url = try report(
            bundleID: "website.refrax.browser.debug",
            procPath: "/Users/USER/*/Refrax.app/Contents/MacOS/Refrax",
        )
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(!CrashMonitor.isFromThisBuild(url, bundleID: release))
        #expect(CrashMonitor.isFromThisBuild(url, bundleID: "website.refrax.browser.debug"))
    }

    @Test
    func `An engine helper's crash is ours when it runs from our folder`() throws {
        let engine = "Engines/website.refrax.engine.chromium/Chromium.engine/Contents/Frameworks/Refrax Chromium Helper.app"
        let ours = try report(
            bundleID: "website.refrax.engine.chromium.helper",
            procPath: "/Users/USER/Library/Application Support/website.refrax.browser/\(engine)",
        )
        let debugs = try report(
            bundleID: "website.refrax.engine.chromium.helper",
            procPath: "/Users/USER/Library/Application Support/website.refrax.browser.debug/\(engine)",
        )
        defer {
            try? FileManager.default.removeItem(at: ours)
            try? FileManager.default.removeItem(at: debugs)
        }
        #expect(CrashMonitor.isFromThisBuild(ours, bundleID: release))
        #expect(!CrashMonitor.isFromThisBuild(debugs, bundleID: release))
    }
}
