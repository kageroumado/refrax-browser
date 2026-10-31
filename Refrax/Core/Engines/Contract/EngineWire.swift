import Foundation

/// JSON encoding of contract messages for engines outside Refrax's own code.
///
/// Engines are untrusted input (`Engines/CONTRACT.md` §6): every message is
/// size-capped before decoding, decoded against the schema, then validated —
/// URLs re-checked, strings capped, numbers clamped. A message that fails is
/// rejected whole; the adapter counts rejections and treats a flood as a
/// misbehaving engine.
nonisolated enum EngineWire {
    /// Largest event, request, or reply accepted from an engine.
    static let maximumMessageSize = 256 * 1_024
    static let maximumStringLength = 8 * 1_024
    static let maximumURLLength = 64 * 1_024
    static let maximumFavicons = 32

    /// Schemes an engine may report for page URLs.
    static let allowedSchemes: Set<String> = [
        "http", "https", "file", "about", "data", "blob", "chrome-extension", "refrax",
    ]

    static func encode(_ value: some Encodable) throws -> Data {
        try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard data.count <= maximumMessageSize else {
            throw EngineError.malformedMessage("\(data.count) bytes exceeds the \(maximumMessageSize)-byte limit")
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw EngineError.malformedMessage(String(describing: error))
        }
    }

    static func decodeEvent(_ data: Data) throws -> PageEvent {
        try validated(decode(PageEvent.self, from: data))
    }

    static func decodeEngineEvent(_ data: Data) throws -> EngineEvent {
        try validated(decode(EngineEvent.self, from: data))
    }

    static func decodeEngineRequest(_ data: Data) throws -> EngineRequest {
        try validated(decode(EngineRequest.self, from: data))
    }

    static func decodeRequest(_ data: Data) throws -> PageRequestKind {
        try validated(decode(PageRequestKind.self, from: data))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    // MARK: Validation

    static func validated(_ event: PageEvent) throws -> PageEvent {
        switch event {
        case let .navigationStarted(url):
            try .navigationStarted(url: checked(url))
        case let .navigationRedirected(url):
            try .navigationRedirected(url: checked(url))
        case let .navigationCommitted(url, isBackForward):
            try .navigationCommitted(url: checked(url), isBackForward: isBackForward)
        case let .urlChanged(url):
            try .urlChanged(url: checked(url))
        case let .navigationFinished(url, statusCode):
            try .navigationFinished(url: checked(url), statusCode: statusCode.map { min(max($0, 0), 999) })
        case let .navigationFailed(failure):
            try .navigationFailed(failure: NavigationFailure(
                kind: failure.kind,
                url: failure.url.map(checked),
                isProvisional: failure.isProvisional,
                engineCode: failure.engineCode,
                description: capped(failure.description),
            ))
        case let .titleChanged(title):
            .titleChanged(title: capped(title))
        case let .progressChanged(progress):
            .progressChanged(progress: clamped(progress, 0 ... 1))
        case let .faviconsChanged(urls):
            try .faviconsChanged(urls: urls.prefix(maximumFavicons).map(checked))
        case let .themeColorChanged(color):
            .themeColorChanged(color: color.map(clamped))
        case let .topEdgeColorChanged(color):
            .topEdgeColorChanged(color: color.map(clamped))
        case let .hoveredLinkChanged(url):
            try .hoveredLinkChanged(url: url.map(checked))
        case let .zoomChanged(factor):
            .zoomChanged(factor: clamped(factor, 0.1 ... 10))
        case let .downloadProgressed(id, receivedBytes, totalBytes):
            .downloadProgressed(id: capped(id), receivedBytes: max(receivedBytes, 0), totalBytes: totalBytes.map { max($0, 0) })
        case let .downloadFinished(id):
            .downloadFinished(id: capped(id))
        case let .downloadFailed(id, reason):
            .downloadFailed(id: capped(id), reason: capped(reason))
        case let .notificationShown(notification):
            try .notificationShown(notification: validated(notification))
        case let .notificationClosed(id):
            .notificationClosed(id: capped(id))
        case let .findResultChanged(matches, activeMatch, isFinal):
            .findResultChanged(matches: clampedMatches(matches), activeMatch: min(max(activeMatch, 0), clampedMatches(matches)), isFinal: isFinal)
        case let .loadedUnfiltered(url):
            try .loadedUnfiltered(url: checked(url))
        case .devToolsChanged, .loadingChanged, .backForwardChanged, .securityChanged, .mediaChanged, .fullscreenChanged,
             .rendererHealthChanged:
            event
        }
    }

    static func validated(_ event: EngineEvent) throws -> EngineEvent {
        switch event {
        case let .notificationShown(profile, notification):
            try .notificationShown(profile: profile, notification: validated(notification))
        case let .notificationClosed(id):
            .notificationClosed(id: capped(id))
        case let .contentBlockingStatus(status, sha256, reason):
            .contentBlockingStatus(status: status, sha256: sha256.map(capped), reason: reason.map(capped))
        }
    }

    /// Largest request log reply accepted: 2,000 entries of a few hundred bytes each.
    static let maximumRequestLogSize = 4 * 1_024 * 1_024

    static func decodeRequestLog(_ data: Data) throws -> RequestLog {
        guard data.count <= maximumRequestLogSize else {
            throw EngineError.malformedMessage("\(data.count)-byte request log exceeds the \(maximumRequestLogSize)-byte limit")
        }
        let log: LossyRequestLog
        do {
            log = try decoder.decode(LossyRequestLog.self, from: data)
        } catch {
            throw EngineError.malformedMessage(String(describing: error))
        }
        // An entry that doesn't decode or validate is dropped, not the log around it.
        let entries = log.entries.prefix(2_000).compactMap(\.entry).compactMap { entry -> RequestLogEntry? in
            guard var valid = try? RequestLogEntry(
                seq: entry.seq,
                time: entry.time,
                frameURL: entry.frameURL.map(checked),
                url: checked(entry.url),
                type: capped(entry.type),
                method: capped(entry.method),
                decision: entry.decision,
                exactness: entry.exactness,
            ) else { return nil }
            valid.rule = entry.rule.map(capped)
            valid.list = entry.list.map(capped)
            valid.line = entry.line.map { max($0, 0) }
            valid.exceptionRule = entry.exceptionRule.map(capped)
            valid.rewrittenURL = try? entry.rewrittenURL.map(checked)
            valid.csp = entry.csp.map(capped)
            valid.truncated = entry.truncated
            return valid
        }
        return RequestLog(entries: entries, nextSequence: log.nextSequence)
    }

    /// A request log whose entries decode one by one.
    private struct LossyRequestLog: Decodable {
        struct Entry: Decodable {
            let entry: RequestLogEntry?

            init(from decoder: any Decoder) throws {
                entry = try? RequestLogEntry(from: decoder)
            }
        }

        let entries: [Entry]
        let nextSequence: Int64
    }

    static func validated(_ request: EngineRequest) throws -> EngineRequest {
        switch request {
        case let .secret(name):
            guard (1 ... 64).contains(name.count), name.allSatisfy(isSecretNameCharacter) else {
                throw EngineError.malformedMessage("rejected secret name \(name.prefix(80))")
            }
            return request
        }
    }

    private static func isSecretNameCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || ".-_".contains(character))
    }

    private static func validated(_ notification: EngineNotification) throws -> EngineNotification {
        try EngineNotification(
            id: capped(notification.id),
            origin: checked(notification.origin),
            title: capped(notification.title),
            body: capped(notification.body),
            tag: notification.tag.map(capped),
            iconURL: notification.iconURL.map(checked),
            isSilent: notification.isSilent,
        )
    }

    static func validated(_ request: PageRequestKind) throws -> PageRequestKind {
        switch request {
        case let .openURL(url, disposition, userGesture, isNewWindowRequest):
            try .openURL(
                url: checked(url),
                disposition: disposition,
                userGesture: userGesture,
                isNewWindowRequest: isNewWindowRequest,
            )
        case let .navigation(url, kind, initiatorOrigin):
            try .navigation(url: checked(url), kind: kind, initiatorOrigin: initiatorOrigin.map(capped))
        case let .permission(kind, origin):
            try .permission(kind: kind, origin: checked(origin))
        case let .javaScriptDialog(dialog):
            try .javaScriptDialog(dialog: JavaScriptDialog(
                kind: dialog.kind,
                message: capped(dialog.message),
                defaultText: dialog.defaultText.map(capped),
                origin: dialog.origin.map(checked),
            ))
        case let .download(id, url, suggestedFilename, mimeType, totalBytes):
            try .download(
                id: capped(id),
                url: checked(url),
                suggestedFilename: capped(suggestedFilename),
                mimeType: mimeType.map(capped),
                totalBytes: totalBytes.map { max($0, 0) },
            )
        }
    }

    private static func checked(_ url: URL) throws -> URL {
        let string = url.absoluteString
        guard string.utf8.count <= maximumURLLength,
              let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else {
            throw EngineError.malformedMessage("rejected URL \(string.prefix(80))")
        }
        return url
    }

    private static func capped(_ string: String) -> String {
        string.count <= maximumStringLength ? string : String(string.prefix(maximumStringLength))
    }

    /// A find result's match count, between none and a million.
    private static func clampedMatches(_ matches: Int) -> Int {
        min(max(matches, 0), 1_000_000)
    }

    private static func clamped(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : range.lowerBound
    }

    private static func clamped(_ color: RGBAColor) -> RGBAColor {
        RGBAColor(
            red: clamped(color.red, 0 ... 1),
            green: clamped(color.green, 0 ... 1),
            blue: clamped(color.blue, 0 ... 1),
            alpha: clamped(color.alpha, 0 ... 1),
        )
    }
}
