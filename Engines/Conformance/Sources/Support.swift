// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import Foundation

/// Runs its first `run` block only: continuations and replies that must settle exactly once,
/// whichever of a callback or a timeout gets there first.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}

/// A failed expectation; the message says what was expected and what happened.
struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// A test that can't run against this engine (a capability it doesn't declare).
struct Skip: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    if !condition { throw Failure(message()) }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ what: String) throws {
    if actual != expected { throw Failure("\(what): expected \(expected), got \(actual)") }
}

// MARK: - JSON

enum JSON {
    static func data(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed, .sortedKeys])) ?? Data("null".utf8)
    }

    static func string(_ object: Any) -> String {
        String(decoding: data(object), as: UTF8.self)
    }

    static func parse(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// The single case of a contract message: `{"name": {fields}}`.
    static func message(_ data: Data) -> (name: String, fields: [String: Any])? {
        guard let object = parse(data) as? [String: Any], object.count == 1,
              let (name, value) = object.first, let fields = value as? [String: Any]
        else { return nil }
        return (name, fields)
    }

    /// Canonical text of a parsed value, for comparing structures.
    static func canonical(_ object: Any?) -> String {
        guard let object else { return "<nil>" }
        return string(object)
    }
}

// MARK: - Waiting

/// Awaits a callback-style operation, failing with a timeout if `start`'s completion never
/// runs. Everything happens on the main actor.
@MainActor
func callback<T: Sendable>(
    _ what: String,
    timeout: TimeInterval,
    _ start: (@escaping @MainActor (Result<T, Error>) -> Void) -> Void,
) async throws -> T {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
        let once = Once()
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            once.run { continuation.resume(throwing: Failure("\(what) timed out after \(Int(timeout)) s")) }
        }
        start { result in
            once.run { continuation.resume(with: result) }
        }
    }
}

/// Polls `check` on the main actor until it returns a value or `timeout` passes.
@MainActor
@discardableResult
func eventually<T>(
    _ what: @autoclosure () -> String,
    timeout: TimeInterval = 10,
    interval: Duration = .milliseconds(25),
    _ check: () throws -> T?,
) async throws -> T {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        if let value = try check() { return value }
        if Date() > deadline { throw Failure("\(what()) — not within \(timeout) s") }
        try await Task.sleep(for: interval)
    }
}

/// `eventually` for checks that await, such as evaluating in the page.
@MainActor
@discardableResult
func eventuallyAsync<T>(
    _ what: @autoclosure () -> String,
    timeout: TimeInterval = 10,
    interval: Duration = .milliseconds(50),
    _ check: () async throws -> T?,
) async throws -> T {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        if let value = try await check() { return value }
        if Date() > deadline { throw Failure("\(what()) — not within \(timeout) s") }
        try await Task.sleep(for: interval)
    }
}

@MainActor
func pause(_ seconds: Double) async throws {
    try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
}
