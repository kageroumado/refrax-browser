import Foundation

/// The native messaging wire format Chrome and Firefox share: each message is UTF-8 JSON
/// preceded by its length as a 32-bit unsigned integer in native byte order, which is little
/// endian on every Mac.
nonisolated enum NativeMessageFraming {
    /// The largest message a host may send, as in Chrome and Firefox.
    static let maximumIncomingLength = 1_024 * 1_024
    /// The largest message Refrax sends to a host.
    static let maximumOutgoingLength = 64 * 1_024 * 1_024
    static let headerLength = 4

    /// `message` serialized as JSON with its length prefix.
    ///
    /// - Throws: ``NativeMessagingError/invalidMessage`` when `message` is not JSON-serializable,
    ///   ``NativeMessagingError/messageTooLarge`` past ``maximumOutgoingLength``.
    static func frame(_ message: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject([message]) else { throw NativeMessagingError.invalidMessage }
        let json = try JSONSerialization.data(withJSONObject: message, options: [.fragmentsAllowed])
        guard json.count <= maximumOutgoingLength else { throw NativeMessagingError.messageTooLarge }
        var length = UInt32(json.count).littleEndian
        return Data(bytes: &length, count: headerLength) + json
    }

    /// Parses one message body.
    static func decode(_ body: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed])
        } catch {
            throw NativeMessagingError.invalidMessage
        }
    }

    /// Splits a byte stream from a host into message bodies, across reads of any size.
    struct Decoder {
        private var buffer = Data()

        init() {}

        /// Appends `data` and returns every message body it completed, in order.
        ///
        /// - Throws: ``NativeMessagingError/messageTooLarge`` when a header announces more than
        ///   ``maximumIncomingLength`` bytes; the stream cannot continue after that.
        mutating func append(_ data: Data) throws -> [Data] {
            buffer.append(data)
            var bodies: [Data] = []
            while buffer.count >= headerLength {
                let length = Int(buffer.prefix(headerLength).reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
                guard length <= maximumIncomingLength else { throw NativeMessagingError.messageTooLarge }
                guard buffer.count >= headerLength + length else { break }
                bodies.append(Data(buffer.dropFirst(headerLength).prefix(length)))
                buffer = Data(buffer.dropFirst(headerLength + length))
            }
            return bodies
        }
    }
}

/// Why a native messaging call failed. The descriptions match Chrome's, which extensions
/// sometimes compare against.
nonisolated enum NativeMessagingError: Error, LocalizedError, Equatable {
    case invalidHostName
    case hostNotFound
    case forbidden
    case invalidManifest(String)
    case invalidMessage
    case messageTooLarge
    case hostExited
    case communicationFailed

    var errorDescription: String? {
        switch self {
        case .invalidHostName: "Invalid native messaging host name specified."
        case .hostNotFound: "Specified native messaging host not found."
        case .forbidden: "Access to the specified native messaging host is forbidden."
        case let .invalidManifest(reason): "Invalid native messaging host manifest: \(reason)"
        case .invalidMessage: "Message is not valid JSON."
        case .messageTooLarge: "Message exceeds maximum allowed size."
        case .hostExited: "Native host has exited."
        case .communicationFailed: "Error when communicating with the native messaging host."
        }
    }
}
