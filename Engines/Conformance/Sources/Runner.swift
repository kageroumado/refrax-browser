// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import AppKit

/// One named check against a running engine.
struct ConformanceTest {
    let name: String
    /// Seconds before the test counts as hung.
    var timeout: TimeInterval = 60
    let body: @MainActor (Context) async throws -> Void
}

/// What a test works with. Policy a test applies is reset after it, so tests stay independent.
@MainActor
final class Context {
    let bundle: Bundle
    let server: FixtureServer
    let storage: URL
    private(set) var engine: TestEngine
    private var touchedPolicy: Set<String> = []
    private var blockingLists: [String] = []
    /// Extra lines a test reports alongside its result, such as a measured latency.
    private(set) var notes: [String] = []

    init(bundle: Bundle, server: FixtureServer, storage: URL, engine: TestEngine) {
        self.bundle = bundle
        self.server = server
        self.storage = storage
        self.engine = engine
    }

    func url(_ path: String, host: String = "127.0.0.1") -> String {
        server.url(path, host: host)
    }

    func page(_ path: String, host: String = "127.0.0.1", profile: [String: Any] = ["shared": [:]]) async throws -> TestPage {
        let page = try engine.makePage(url(path, host: host), profile: profile)
        try await page.waitForFinish()
        return page
    }

    func apply(_ category: String, _ fields: [String: Any]) {
        touchedPolicy.insert(category)
        engine.apply([category: fields])
    }

    func scripts(_ scripts: [[String: Any]]) {
        apply("scripts", ["scripts": scripts])
    }

    func note(_ line: String) {
        notes.append(line)
    }

    func contentBlocking(enabled: Bool = true, lists: [String], allowlistedHosts: [String] = []) {
        blockingLists = lists
        apply("contentBlocking", [
            "policy": [
                "isEnabled": enabled,
                "lists": lists.enumerated().map { ["id": "list\($0.offset)", "contents": $0.element] },
                "allowlistedHosts": allowlistedHosts,
            ],
        ])
    }

    /// A fresh engine instance from the same bundle, started on the same storage.
    func restartEngine() async throws {
        engine.closeAll()
        engine = try TestEngine(bundle: bundle)
        try await engine.start(storage: storage)
        touchedPolicy.removeAll()
    }

    func tearDown() {
        engine.closeAll()
        if touchedPolicy.contains("scripts") {
            engine.apply(["scripts": ["scripts": []]])
        }
        if touchedPolicy.contains("contentBlocking") {
            // Off, but with the same lists: the next test that turns blocking on doesn't wait
            // for its lists to be compiled and indexed again.
            contentBlocking(enabled: false, lists: blockingLists)
        }
        touchedPolicy.removeAll()
        notes.removeAll()
    }
}

@MainActor
struct Runner {
    let bundle: Bundle
    let storage: URL
    let filter: [String]
    let tests: [ConformanceTest]

    /// Runs every selected test; returns whether all passed.
    func run() async -> Bool {
        let selected = tests.filter { test in filter.isEmpty || filter.contains { test.name.contains($0) } }
        let name = bundle.object(forInfoDictionaryKey: RFXEngineInfoKey.displayName.rawValue) as? String ?? bundle.bundleURL.lastPathComponent
        let version = bundle.object(forInfoDictionaryKey: RFXEngineInfoKey.engineVersion.rawValue) as? String ?? "?"
        report("engine-conformance: \(name) (\(version)), \(selected.count) tests")

        let server = FixtureServer()
        let context: Context
        do {
            try await server.start()
            let engine = try TestEngine(bundle: bundle)
            let started = Date()
            try await engine.startFromNestedLoop(storage: storage)
            report("started from a nested run loop in \(String(format: "%.2f", -started.timeIntervalSinceNow)) s; fixtures on port \(server.port)")
            context = Context(bundle: bundle, server: server, storage: storage, engine: engine)
        } catch {
            report("FAIL could not start: \(error)")
            return false
        }

        var passed = 0, failed: [String] = [], skipped = 0
        let began = Date()
        for test in selected {
            let started = Date()
            let outcome = await run(test, in: context)
            let seconds = String(format: "%.2f", -started.timeIntervalSinceNow)
            switch outcome {
            case .passed:
                passed += 1
                report("ok   \(test.name) (\(seconds) s)")
                context.notes.forEach { report("     \($0)") }
            case let .skipped(reason):
                skipped += 1
                report("skip \(test.name): \(reason)")
            case let .failed(reason):
                failed.append(test.name)
                report("FAIL \(test.name) (\(seconds) s): \(reason)")
                context.notes.forEach { report("     \($0)") }
            }
            context.tearDown()
        }
        server.stop()
        context.engine.host.shutdown()
        report("\(passed) passed, \(failed.count) failed, \(skipped) skipped in \(Int(-began.timeIntervalSinceNow)) s")
        if !failed.isEmpty {
            report("failed: \(failed.joined(separator: " "))")
        }
        return failed.isEmpty
    }

    private enum Outcome {
        case passed
        case skipped(String)
        case failed(String)
    }

    private func run(_ test: ConformanceTest, in context: Context) async -> Outcome {
        do {
            try await callback(test.name, timeout: test.timeout) { (done: @escaping @MainActor (Result<Void, Error>) -> Void) in
                Task { @MainActor in
                    do {
                        try await test.body(context)
                        done(.success(()))
                    } catch {
                        done(.failure(error))
                    }
                }
            }
            return .passed
        } catch let skip as Skip {
            return .skipped(skip.description)
        } catch {
            return .failed("\(error)")
        }
    }

    private func report(_ line: String) {
        print(line)
        fflush(stdout)
    }
}
