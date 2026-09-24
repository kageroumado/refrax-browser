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
    static let maximumMessageSize = 256 * 1024
    static let maximumStringLength = 8 * 1024
    static let maximumURLLength = 64 * 1024
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
            return try .navigationStarted(url: checked(url))
        case let .navigationRedirected(url):
            return try .navigationRedirected(url: checked(url))
        case let .navigationCommitted(url, isBackForward):
            return try .navigationCommitted(url: checked(url), isBackForward: isBackForward)
        case let .sameDocumentNavigation(url):
            return try .sameDocumentNavigation(url: checked(url))
        case let .navigationFinished(url, statusCode):
            return try .navigationFinished(url: checked(url), statusCode: statusCode.map { min(max($0, 0), 999) })
        case let .navigationFailed(failure):
            return try .navigationFailed(failure: NavigationFailure(
                kind: failure.kind,
                url: failure.url.map(checked),
                isProvisional: failure.isProvisional,
                engineCode: failure.engineCode,
                description: capped(failure.description),
            ))
        case let .titleChanged(title):
            return .titleChanged(title: capped(title))
        case let .progressChanged(progress):
            return .progressChanged(progress: clamped(progress, 0 ... 1))
        case let .faviconsChanged(urls):
            return try .faviconsChanged(urls: urls.prefix(maximumFavicons).map(checked))
        case let .themeColorChanged(color):
            return .themeColorChanged(color: color.map(clamped))
        case let .topEdgeColorChanged(color):
            return .topEdgeColorChanged(color: color.map(clamped))
        case let .hoveredLinkChanged(url):
            return try .hoveredLinkChanged(url: url.map(checked))
        case let .zoomChanged(factor):
            return .zoomChanged(factor: clamped(factor, 0.1 ... 10))
        case .loadingChanged, .backForwardChanged, .securityChanged, .mediaChanged, .fullscreenChanged,
             .rendererHealthChanged:
            return event
        }
    }

    static func validated(_ request: PageRequestKind) throws -> PageRequestKind {
        switch request {
        case let .openURL(url, disposition, userGesture):
            return try .openURL(url: checked(url), disposition: disposition, userGesture: userGesture)
        case let .permission(kind, origin):
            return try .permission(kind: kind, origin: checked(origin))
        case let .javaScriptDialog(dialog):
            return try .javaScriptDialog(dialog: JavaScriptDialog(
                kind: dialog.kind,
                message: capped(dialog.message),
                defaultText: dialog.defaultText.map(capped),
                origin: dialog.origin.map(checked),
            ))
        case let .download(url, suggestedFilename, mimeType):
            return try .download(
                url: checked(url),
                suggestedFilename: capped(suggestedFilename),
                mimeType: mimeType.map(capped),
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
