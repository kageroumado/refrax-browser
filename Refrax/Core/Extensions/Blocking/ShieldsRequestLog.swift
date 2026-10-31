import Foundation
import Observation

/// What Shields did to one WebKit page's loads, newest 2,000 kept.
///
/// WebKit reports only the loads a rule list acted on (blocked, redirected), with the URL and
/// the list, so entries start as decisions without a rule; ``attributed(using:lists:)`` names
/// the rule by asking the app's engine the same question, with the page as the source and the
/// request type guessed from the URL.
@Observable
final class ShieldsRequestLog {
    private enum Constants {
        static let capacity = 2_000
    }

    /// Oldest first.
    private(set) var entries: [RequestLogEntry] = []
    @ObservationIgnored private var nextSequence: Int64 = 1

    /// How many loads Shields blocked or redirected since the page last committed a document.
    private(set) var blockedCount = 0

    func record(url: URL, frameURL: URL?, decision: RequestLogEntry.Decision) {
        entries.append(RequestLogEntry(
            seq: nextSequence,
            time: .now,
            frameURL: frameURL,
            url: url,
            type: ShieldsRequestType(guessingFrom: url).rawValue,
            method: "GET",
            decision: decision,
            exactness: .attributed,
        ))
        nextSequence += 1
        if entries.count > Constants.capacity {
            entries.removeFirst(entries.count - Constants.capacity)
        }
        if decision == .blocked || decision == .redirected {
            blockedCount += 1
        }
    }

    /// Restarts the page count when a new document commits; the entries stay.
    func documentCommitted() {
        blockedCount = 0
    }

    func log(since sequence: Int64) -> RequestLog {
        RequestLog(entries: entries.filter { $0.seq > sequence }, nextSequence: nextSequence - 1)
    }
}

nonisolated extension RequestLog {
    /// Entries with `rule`, `list`, `line` and `exceptionRule` filled from `engine` where the
    /// engine that logged them left them out. `lists` maps a source index to a list id.
    func attributed(using engine: ShieldsEngine?, lists: [Int: String]) -> RequestLog {
        guard let engine else { return self }
        let entries = entries.map { entry -> RequestLogEntry in
            guard entry.rule == nil, entry.decision != .allowed else { return entry }
            let source = entry.frameURL?.absoluteString ?? entry.url.absoluteString
            guard let explanation = engine.explain(
                url: entry.url.absoluteString,
                source: source,
                type: entry.type,
                method: entry.method.isEmpty ? "GET" : entry.method,
            ) else { return entry }
            var named = entry
            named.rule = explanation.rule?.text
            named.list = explanation.rule?.sourceIndex.flatMap { lists[$0] }
            named.line = explanation.rule?.line
            named.exceptionRule = explanation.exception?.text
            if named.rewrittenURL == nil, let rewritten = explanation.rewrittenUrl {
                named.rewrittenURL = URL(string: rewritten)
            }
            return named
        }
        return RequestLog(entries: entries, nextSequence: nextSequence)
    }
}
