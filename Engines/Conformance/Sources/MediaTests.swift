// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import Foundation

/// `setMediaSuspended` (CONTRACT.md §4.2): every player pauses and stays paused until resumed.
enum MediaTests {
    static let all: [ConformanceTest] = [
        ConformanceTest(name: "media.suspend-and-resume", timeout: 60) { context in
            let page = try await context.page("/html/media")
            defer { page.close() }
            let paused = "document.getElementById('player').paused"
            _ = try? await page.evaluate("document.getElementById('player').play().then(() => 'played', e => String(e))", gesture: true)
            try await eventuallyAsync("the tone to play", timeout: 10) {
                try await page.evaluate(paused) as? Bool == false ? true : nil
            }
            page.command("setMediaSuspended", ["suspended": true])
            try await eventuallyAsync("the player to pause", timeout: 10) {
                try await page.evaluate(paused) as? Bool == true ? true : nil
            }
            // The page can't start it again while suspended.
            _ = try? await page.evaluate("document.getElementById('player').play().then(() => 'played', e => String(e))")
            try await pause(1)
            try expectEqual(try await page.evaluate(paused) as? Bool, true, "a suspended page's player after play()")
            page.command("setMediaSuspended", ["suspended": false])
            try await eventuallyAsync("the player to resume", timeout: 10) {
                try await page.evaluate(paused) as? Bool == false ? true : nil
            }
        },
    ]
}
