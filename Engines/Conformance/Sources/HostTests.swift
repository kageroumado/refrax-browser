// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import Darwin
import Foundation

/// An out-of-process engine's processes dying under Refrax (CONTRACT.md §3). Run last: they
/// kill the engine.
enum HostTests {
    /// Every process the runner started, which for an out-of-process engine is its host.
    static func childProcesses() -> [pid_t] {
        var pids = [pid_t](repeating: 0, count: 256)
        let count = proc_listchildpids(getpid(), &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return count > 0 ? Array(pids.prefix(Int(count))) : []
    }

    static let all: [ConformanceTest] = [
        ConformanceTest(name: "host.death-is-reported") { context in
            let outOfProcess = context.bundle.object(forInfoDictionaryKey: RFXEngineInfoKey.outOfProcess.rawValue) as? Bool ?? false
            guard outOfProcess else { throw Skip("in-process engine") }
            let page = try await context.page("/html/basic")
            let children = childProcesses()
            try expect(!children.isEmpty, "no engine processes to kill")
            children.forEach { kill($0, SIGKILL) }
            let reason = try await eventually("engineHostDidTerminate", timeout: 15) { context.engine.terminationReason }
            context.note("reason: \(reason)")
            // Calls into a dead engine must complete, never hang.
            _ = try? await page.evaluateRaw("1", timeout: 10)
        },

        ConformanceTest(name: "host.restart-after-death", timeout: 120) { context in
            let outOfProcess = context.bundle.object(forInfoDictionaryKey: RFXEngineInfoKey.outOfProcess.rawValue) as? Bool ?? false
            guard outOfProcess else { throw Skip("in-process engine") }
            if context.engine.terminationReason == nil {
                childProcesses().forEach { kill($0, SIGKILL) }
                _ = try await eventually("engineHostDidTerminate", timeout: 15) { context.engine.terminationReason }
            }
            let started = Date()
            try await context.restartEngine()
            context.note(String(format: "restarted in %.2f s", -started.timeIntervalSinceNow))
            let page = try await context.page("/html/basic")
            try expectEqual(try await page.evaluate("document.title") as? String, "basic", "a page in the restarted engine")
        },
    ]
}
