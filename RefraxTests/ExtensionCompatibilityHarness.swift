import Foundation
import Testing
import WebKit
@testable import Refrax

/// The folder of extensions to run the harness on, from `REFRAX_EXTENSION_COMPAT_DIR`.
private nonisolated enum CompatibilityFolder {
    static var url: URL? {
        ProcessInfo.processInfo.environment["REFRAX_EXTENSION_COMPAT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}

/// Loads real extensions the way an install does and records what they need that Refrax
/// lacks: API members they read that are absent, calls that throw or reject, uncaught
/// errors, permissions WebKit does not know, and whether the background, content scripts,
/// popup and options page come up.
///
/// It runs only when `REFRAX_EXTENSION_COMPAT_DIR` names a folder of `.xpi` and `.crx` files,
/// which `Scripts/extension-compat.sh` downloads; it writes `report.json` and `report.md`
/// there. Nothing in it needs the network beyond what the extensions themselves fetch.
@Suite(
    "Extension compatibility harness",
    .serialized,
    .enabled(if: CompatibilityFolder.url != nil, "Set REFRAX_EXTENSION_COMPAT_DIR to a folder of extensions"),
)
@MainActor
struct ExtensionCompatibilityHarness {
    /// Permissions Refrax provides with shims where WebKit has none.
    private static let shimmedPermissions: Set<String> = ["downloads", "idle", "notifications", "privacy"]

    private enum Timing {
        static let background = Duration.seconds(20)
        static let settle = Duration.seconds(4)
        static let page = Duration.seconds(5)
    }

    private static let fixturePage = """
    <!doctype html>
    <html><head><title>Compatibility fixture</title></head>
    <body>
    <h1>Fixture</h1>
    <p><a href="https://example.com/">A link</a> and some text for readers and dark modes.</p>
    <form><input type="email" name="email" autocomplete="username">
    <input type="password" name="password" autocomplete="current-password"><button>Sign in</button></form>
    <video width="160" height="90"></video>
    </body></html>
    """

    @Test
    func `Every extension in the folder, loaded and exercised`() async throws {
        let directory = try #require(CompatibilityFolder.url)
        let archives = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["xpi", "crx"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let server = try LoopbackHTTPServer(responses: ["/fixture.html": .init(contentType: "text/html", body: Self.fixturePage)])
        try await server.start()
        defer { server.stop() }

        var reports: [[String: Any]] = []
        for archive in archives {
            await reports.append(exercise(archive, in: directory, page: server.url("/fixture.html")))
        }

        let json = try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: directory.appendingPathComponent("report.json"))
        try Self.markdown(reports).write(to: directory.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
    }

    // MARK: - One extension

    private func exercise(_ archive: URL, in directory: URL, page: URL) async -> [String: Any] {
        var report: [String: Any] = ["archive": archive.lastPathComponent]
        do {
            try await exercise(archive, in: directory, page: page, into: &report)
        } catch {
            report["failure"] = String(describing: error)
        }
        return report
    }

    private func exercise(_ archive: URL, in directory: URL, page: URL, into report: inout [String: Any]) async throws {
        let folder = directory.appendingPathComponent(".extracted", isDirectory: true)
            .appendingPathComponent(archive.deletingPathExtension().lastPathComponent, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try await ExtensionArchive.extract(archive, into: folder)

        let recorder = ProbeRecorder()
        let webViewConfiguration = WKWebViewConfiguration()
        let pageScripts = webViewConfiguration.userContentController
        let controllerConfiguration = WKWebExtensionController.Configuration.nonPersistent()
        controllerConfiguration.webViewConfiguration = webViewConfiguration
        let env = try TabManagerTestEnvironment(extensionControllerConfiguration: controllerConfiguration)
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)
        // After the shims, which the manager installed on the same user content controller.
        try pageScripts.addUserScript(WKUserScript(source: Self.probe(role: "page"), injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        pageScripts.add(recorder, contentWorld: .page, name: ProbeRecorder.name)

        let webExtension = try await WKWebExtension(resourceBaseURL: folder)
        let manifest = webExtension.manifest
        report["name"] = webExtension.displayName ?? archive.lastPathComponent
        report["version"] = webExtension.displayVersion ?? ""
        report["manifestVersion"] = webExtension.manifestVersion
        report["background"] = Self.backgroundKind(manifest)
        report["manifestWarnings"] = webExtension.errors.map(\.localizedDescription)
        report["permissions"] = permissionReport(webExtension)

        let context = WKWebExtensionContext(for: webExtension)
        let identifier = ExtensionContextIdentifier.identifier(installedID: UUID().uuidString, spaceID: nil)
        context.uniqueIdentifier = identifier
        context.baseURL = ExtensionContextIdentifier.baseURL(for: identifier)
        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        for pattern in webExtension.requestedPermissionMatchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
        let contentWorld = WKContentWorld.world(name: "WebExtension-\(identifier)")
        let pagesScripts = env.browserState.webPageConfiguration.userContentController
        try pagesScripts.addUserScript(WKUserScript(source: Self.probe(role: "content"), injectionTime: .atDocumentStart, forMainFrameOnly: false, in: contentWorld))
        pagesScripts.add(recorder, contentWorld: contentWorld, name: ProbeRecorder.name)
        defer {
            pagesScripts.removeAllUserScripts()
            pagesScripts.removeScriptMessageHandler(forName: ProbeRecorder.name, contentWorld: contentWorld)
        }

        try env.extensionManager.defaultController.load(context)
        report["backgroundLoad"] = await loadBackground(of: context)
        try await Task.sleep(for: Timing.settle)

        recorder.phase = "page"
        env.tabManager.createTab(url: page, in: space, makeActive: false, loadImmediately: true)
        try await Task.sleep(for: Timing.page)
        report["injectsIntoFixturePage"] = context.hasInjectedContent(for: page)

        if let action = context.action(for: nil), action.presentsPopup {
            recorder.phase = "popup"
            report["popupLoaded"] = action.popupWebView != nil
            try await Task.sleep(for: Timing.page)
            action.closePopup()
        }
        if context.optionsPageURL != nil {
            recorder.phase = "options"
            do {
                try await env.extensionManager.openOptionsPage(for: context)
                try await Task.sleep(for: Timing.page)
                report["optionsOpened"] = true
            } catch {
                report["optionsOpened"] = String(describing: error)
            }
        }

        report["contextErrors"] = context.errors.map(\.localizedDescription)
        report["probe"] = recorder.summary()
        try? env.extensionManager.defaultController.unload(context)
    }

    /// Starts the background and waits for it, at most ``Timing/background``.
    private func loadBackground(of context: WKWebExtensionContext) async -> String {
        guard context.webExtension.hasBackgroundContent else { return "none" }
        let outcome = BackgroundOutcome()
        context.loadBackgroundContent { error in
            outcome.result = error.map { "error: \($0.localizedDescription)" } ?? "loaded"
        }
        return await (try? waitFor(timeout: Timing.background, "the background") { outcome.result }) ?? "timed out"
    }

    private final class BackgroundOutcome {
        var result: String?
    }

    private func permissionReport(_ webExtension: WKWebExtension) -> [String: Any] {
        let manifest = webExtension.manifest
        let declared = ((manifest["permissions"] as? [String] ?? []) + (manifest["optional_permissions"] as? [String] ?? []))
            .filter { !$0.contains("://") && $0 != "<all_urls>" }
        let known = Set(webExtension.requestedPermissions.union(webExtension.optionalPermissions).map(\.rawValue))
        let unknown = declared.filter { !known.contains($0) }
        return [
            "declared": declared,
            "unknownToWebKit": unknown.filter { !Self.shimmedPermissions.contains($0) },
            "shimmedByRefrax": unknown.filter { Self.shimmedPermissions.contains($0) },
        ]
    }

    private static func backgroundKind(_ manifest: [String: Any]) -> String {
        guard let background = manifest["background"] as? [String: Any] else { return "none" }
        if background["service_worker"] != nil {
            return background["type"] as? String == "module" ? "service worker (module)" : "service worker"
        }
        let persistent = background["persistent"] as? Bool ?? true
        return background["page"] != nil ? (persistent ? "page" : "event page") : (persistent ? "scripts" : "event scripts")
    }

    private static func probe(role: String) throws -> String {
        try String(contentsOf: testResourceURL("extension-compat-probe.js"), encoding: .utf8)
            .replacingOccurrences(of: "__ROLE__", with: role)
    }

    // MARK: - Report

    private static func markdown(_ reports: [[String: Any]]) -> String {
        var lines = ["# Extension compatibility harness", ""]
        for report in reports {
            lines.append("## \(report["name"] ?? report["archive"] ?? "?") \(report["version"] ?? "")")
            lines.append("")
            for key in ["archive", "failure", "manifestVersion", "background", "backgroundLoad", "injectsIntoFixturePage", "popupLoaded", "optionsOpened"] {
                if let value = report[key] {
                    lines.append("- \(key): \(value)")
                }
            }
            if let permissions = report["permissions"] as? [String: Any] {
                lines.append("- permissions unknown to WebKit: \(permissions["unknownToWebKit"] ?? [])")
                lines.append("- permissions shimmed by Refrax: \(permissions["shimmedByRefrax"] ?? [])")
            }
            for key in ["manifestWarnings", "contextErrors"] {
                if let values = report[key] as? [String], !values.isEmpty {
                    lines.append("- \(key):")
                    lines += values.map { "  - \($0)" }
                }
            }
            if let probe = report["probe"] as? [String: Any] {
                for (key, value) in probe.sorted(by: { $0.key < $1.key }) {
                    guard let entries = value as? [String], !entries.isEmpty else { continue }
                    lines.append("- \(key):")
                    lines += entries.map { "  - \($0)" }
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

/// Collects the probe's records from extension pages and content script worlds.
@MainActor
private final class ProbeRecorder: NSObject, WKScriptMessageHandler {
    static let name = "refraxCompatProbe"

    /// What the harness is doing when a record arrives: background, page, popup, options.
    var phase = "background"
    private var records: [(phase: String, body: [String: Any])] = []

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        records.append((phase, body))
    }

    /// Each kind of record, deduplicated with counts: `api (role, phase) ×n: message`.
    func summary() -> [String: Any] {
        var groups: [String: [String: Int]] = [:]
        var alive: Set<String> = []
        for (phase, body) in records {
            let type = body["type"] as? String ?? "?"
            let role = body["role"] as? String ?? "?"
            if type == "alive" {
                alive.insert("\(role) in \(phase): \(Self.shortPage(body["page"]))")
                continue
            }
            let api = body["api"] as? String ?? ""
            var line = api.isEmpty ? "" : api
            if let message = body["message"] as? String {
                line += (line.isEmpty ? "" : ": ") + String(message.prefix(160))
            }
            if let source = body["source"] as? String, !source.isEmpty {
                line += " @ \(Self.shortPage(source)):\(body["line"] ?? "")"
            }
            line += " [\(role), \(phase)]"
            groups[type, default: [:]][line, default: 0] += 1
        }
        var summary: [String: Any] = ["alive": alive.sorted()]
        for (type, lines) in groups {
            summary[type] = lines.sorted { $0.key < $1.key }.map { $0.value > 1 ? "\($0.key) ×\($0.value)" : $0.key }
        }
        return summary
    }

    private static func shortPage(_ page: Any?) -> String {
        guard let page = page as? String, let url = URL(string: page) else { return "?" }
        return url.scheme == "webkit-extension" ? url.path : (url.host() ?? page) + url.path
    }
}
