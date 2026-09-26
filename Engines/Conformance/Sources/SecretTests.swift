// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import Foundation

/// Secrets (CONTRACT.md §4.6): an engine's key material comes from Refrax, and loading never
/// waits on a keychain.
enum SecretTests {
    static let all: [ConformanceTest] = [
        ConformanceTest(name: "secrets.storage-key-comes-from-refrax") { context in
            try expect(context.engine.secretRequests.contains("storageKey"), "secrets asked for: \(context.engine.secretRequests)")
            let cookie = "kept\(UUID().uuidString.prefix(8))=yes"
            let page = try await context.page("/html/basic")
            _ = try await page.evaluate("document.cookie = '\(cookie); max-age=3600; path=/'")
            try await page.load(context.url("/html/other"))
            let cookies = try await page.evaluate("document.cookie") as? String ?? ""
            try expect(cookies.split(separator: "; ").contains(Substring(cookie)), "\(cookie) on the next document: \(cookies)")
        },

        ConformanceTest(name: "secrets.unavailable-never-blocks-loading", timeout: 120) { context in
            // A locked keychain: Refrax answers `unavailable`, and HTTP loads, which read the
            // cookie store, still finish.
            try await context.restartEngine { _ in nil }
            do {
                try expect(context.engine.secretRequests.contains("storageKey"), "secrets asked for: \(context.engine.secretRequests)")
                let page = try await context.page("/html/basic")
                try expectEqual(try await page.evaluate("document.title") as? String, "basic", "a page without the storage key")
            } catch {
                try? await context.restartEngine()
                throw error
            }
            try await context.restartEngine()
            let page = try await context.page("/html/basic")
            try expectEqual(try await page.evaluate("document.title") as? String, "basic", "a page once the key is back")
        },
    ]
}
