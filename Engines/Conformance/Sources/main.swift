// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.
//
// engine-conformance: checks an engine bundle against the engine contract (Engines/CONTRACT.md)
// by driving it through RFXEngine.h as Refrax does, against fixtures it serves on loopback.
//
//   engine-conformance <path/to/X.engine> [--storage DIR] [--status FILE] [--list] [name-substring …]
//
// Prints one line per test and exits 0 when every selected test passes; --status also writes
// that exit code to FILE, for a launch through `open`, which reports none. Storage defaults to
// a fresh temporary directory. The input tests need the runner to be the active app, which
// macOS grants an app launched through LaunchServices (forge conformance does).

import AppKit

@MainActor
final class Conformance: NSObject, NSApplicationDelegate {
    static let tests: [ConformanceTest] = EvaluationTests.all + ScriptTests.all + RequestTests.all + NotificationTests.all
        + NavigationTests.all + BlockingTests.all + StabilityTests.all + InputTests.all
        + SecretTests.all + HostTests.all

    let bundleURL: URL
    let storage: URL
    let status: URL?
    let filter: [String]

    init(bundleURL: URL, storage: URL, status: URL?, filter: [String]) {
        self.bundleURL = bundleURL
        self.storage = storage
        self.status = status
        self.filter = filter
    }

    func finish(_ code: Int32) -> Never {
        if let status {
            try? Data("\(code)\n".utf8).write(to: status)
        }
        exit(code)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.menu()
        Task { @MainActor in
            guard let bundle = Bundle(url: bundleURL) else {
                print("no bundle at \(bundleURL.path)")
                finish(2)
            }
            let passed = await Runner(bundle: bundle, storage: storage, filter: filter, tests: Self.tests).run()
            finish(passed ? 0 : 1)
        }
    }

    /// Edit's standard items, and a ⌘J item the input tests count.
    static func menu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenuItem()
        app.submenu = NSMenu(title: "engine-conformance")
        main.addItem(app)
        let edit = NSMenuItem()
        edit.submenu = NSMenu(title: "Edit")
        edit.submenu!.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.submenu!.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.submenu!.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(edit)
        let probe = NSMenuItem()
        probe.submenu = NSMenu(title: "Probe")
        let item = probe.submenu!.addItem(withTitle: "Conformance Key", action: #selector(InputTests.MenuProbe.conformanceKey(_:)), keyEquivalent: "j")
        item.target = InputTests.MenuProbe.shared
        main.addItem(probe)
        return main
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty || arguments.first == "--help" {
    print("usage: engine-conformance <X.engine> [--storage DIR] [--status FILE] [--list] [name-substring …]")
    exit(2)
}
if arguments.contains("--list") {
    MainActor.assumeIsolated {
        Conformance.tests.forEach { print($0.name) }
    }
    exit(0)
}

var storage = FileManager.default.temporaryDirectory.appending(path: "engine-conformance-\(UUID().uuidString)", directoryHint: .isDirectory)
var status: URL?
var filter: [String] = []
var index = 1
while index < arguments.count {
    if arguments[index] == "--storage", index + 1 < arguments.count {
        storage = URL(filePath: arguments[index + 1], directoryHint: .isDirectory)
        index += 2
    } else if arguments[index] == "--status", index + 1 < arguments.count {
        status = URL(filePath: arguments[index + 1])
        index += 2
    } else {
        filter.append(arguments[index])
        index += 1
    }
}
try? FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)

MainActor.assumeIsolated {
    let delegate = Conformance(bundleURL: URL(filePath: arguments[0]), storage: storage, status: status, filter: filter)
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
