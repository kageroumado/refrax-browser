import Foundation
import Synchronization

/// A running native messaging host: an executable that reads framed JSON messages on stdin
/// and writes framed replies on stdout, as Chrome and Firefox run it.
///
/// The host starts in its executable's directory with the arguments its manifest's format
/// prescribes. Its stderr goes to the extensions log. The host exits, or is treated as
/// exited, when its stdout closes or it sends an oversized message.
final class NativeMessagingHostProcess {
    /// What the host did, delivered on the main actor in the order it happened.
    nonisolated enum Event {
        /// A message body the host wrote, still JSON.
        case message(Data)
        /// The host closed its output; nothing follows.
        case closed(NativeMessagingError)
    }

    let host: ResolvedNativeMessagingHost
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private let writer = DispatchQueue(label: "website.refrax.native-messaging.writer")
    private let onEvent: (Event) -> Void
    private var isClosed = false

    private enum Timing {
        /// How long a host has to exit after SIGTERM before it is killed, as in Chrome.
        static let killDelay = Duration.seconds(2)
    }

    /// Creates a host process; nothing runs until ``start()``.
    ///
    /// - Parameters:
    ///   - host: The resolved host to run.
    ///   - onEvent: Receives the host's messages and its exit, on the main actor.
    init(host: ResolvedNativeMessagingHost, onEvent: @escaping (Event) -> Void) {
        self.host = host
        self.onEvent = onEvent
    }

    /// Launches the host.
    ///
    /// - Throws: ``NativeMessagingError/communicationFailed`` when the executable cannot start.
    func start() throws {
        process.executableURL = host.executableURL
        process.arguments = host.arguments
        process.currentDirectoryURL = host.executableURL.deletingLastPathComponent()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput
        // A host that exits early must not take Refrax down with SIGPIPE on the next write.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        let reader = FrameReader()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            let events: [Event]
            if data.isEmpty {
                handle.readabilityHandler = nil
                events = [.closed(.hostExited)]
            } else {
                do {
                    events = try reader.append(data).map(Event.message)
                } catch {
                    handle.readabilityHandler = nil
                    events = [.closed(error as? NativeMessagingError ?? .communicationFailed)]
                }
            }
            // Main-queue delivery keeps the host's messages in order.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for event in events {
                        self?.deliver(event)
                    }
                }
            }
        }
        let name = host.name
        errorOutput.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            Logger.debug("Native host \(name): \(String(decoding: data, as: UTF8.self))", category: Logger.extensions)
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errorOutput.fileHandleForReading.readabilityHandler = nil
            Logger.error("Failed to start native host \(host.name): \(error)", category: Logger.extensions)
            throw NativeMessagingError.communicationFailed
        }
    }

    /// Writes `message` to the host's stdin, framed. Writes happen in order off the main
    /// actor, so a host that stops reading never blocks the browser.
    ///
    /// - Throws: ``NativeMessagingError/hostExited`` after the host closed;
    ///   ``NativeMessageFraming/frame(_:)``'s errors for a message that cannot be sent.
    func send(_ message: Any) throws {
        guard !isClosed else { throw NativeMessagingError.hostExited }
        let frame = try NativeMessageFraming.frame(message)
        let handle = input.fileHandleForWriting
        let name = host.name
        writer.async {
            do {
                try handle.write(contentsOf: frame)
            } catch {
                Logger.debug("Native host \(name) stopped reading: \(error)", category: Logger.extensions)
            }
        }
    }

    /// Stops the host: closes its stdin, sends SIGTERM, and SIGKILL if it outlives
    /// ``Timing/killDelay``. No event follows.
    func terminate() {
        guard !isClosed else { return }
        isClosed = true
        output.fileHandleForReading.readabilityHandler = nil
        let handle = input.fileHandleForWriting
        writer.async {
            try? handle.close()
        }
        guard process.isRunning else { return }
        process.terminate()
        let process = process
        Task(name: "Kill native host") {
            try? await Task.sleep(for: Timing.killDelay)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    private func deliver(_ event: Event) {
        guard !isClosed else { return }
        if case .closed = event {
            isClosed = true
        }
        onEvent(event)
    }
}

/// The host's stdout framing state, read from the file handle's serial callback queue.
private final nonisolated class FrameReader: Sendable {
    private let decoder = Mutex(NativeMessageFraming.Decoder())

    func append(_ data: Data) throws -> [Data] {
        try decoder.withLock { try $0.append(data) }
    }
}
