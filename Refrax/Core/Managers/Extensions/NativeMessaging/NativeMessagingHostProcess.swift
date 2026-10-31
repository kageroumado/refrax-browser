import Darwin
import Foundation
import Synchronization

/// A running native messaging host: an executable that reads framed JSON messages on stdin
/// and writes framed replies on stdout, as Chrome and Firefox run it.
///
/// The host starts in its executable's directory with the arguments its manifest's format
/// prescribes, a minimal environment, and no share in Refrax's privacy grants: it is spawned
/// as responsible for itself, so camera, microphone or screen access Refrax holds does not
/// extend to it. Its stderr goes to the extensions log.
///
/// The host's output ends when it closes stdout or sends an oversized message; the host is
/// then stopped. Stopping closes its stdin, sends SIGTERM, and SIGKILL if it outlives
/// ``Timing/killDelay``.
final class NativeMessagingHostProcess {
    /// What the host did, delivered on the main actor in the order it happened.
    nonisolated enum Event {
        /// A message body the host wrote, still JSON.
        case message(Data)
        /// The host's output ended; nothing follows.
        case closed(NativeMessagingError)
    }

    let host: ResolvedNativeMessagingHost
    private let input = Pipe()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private let writer = DispatchQueue(label: "website.refrax.native-messaging.writer")
    private let onEvent: (Event) -> Void
    private let exitWatch = ExitWatch()
    /// The host's process, once started.
    private(set) var processIdentifier: pid_t?
    /// The host's output ended; no more events go out.
    private var isOutputClosed = false
    /// ``terminate()`` ran.
    private var isTerminated = false

    /// The process exited and was reaped.
    var hasExited: Bool {
        exitWatch.hasExited
    }

    private enum Timing {
        /// How long a host has to exit after SIGTERM before it is killed, as in Chrome.
        static let killDelay = Duration.seconds(2)
    }

    /// The environment a host gets: enough to find its home and temporary folder.
    private static var environment: [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        for key in ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "__CF_USER_TEXT_ENCODING"] {
            environment[key] = inherited[key]
        }
        return environment
    }

    /// Creates a host process; nothing runs until ``start()``.
    ///
    /// - Parameters:
    ///   - host: The resolved host to run.
    ///   - onEvent: Receives the host's messages and the end of its output, on the main actor.
    init(host: ResolvedNativeMessagingHost, onEvent: @escaping (Event) -> Void) {
        self.host = host
        self.onEvent = onEvent
    }

    isolated deinit {
        terminate()
    }

    /// Launches the host.
    ///
    /// - Throws: ``NativeMessagingError/communicationFailed`` when the executable cannot start.
    func start() throws {
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

        let pid: pid_t
        do {
            pid = try HostSpawner.spawn(
                executable: host.executableURL,
                arguments: host.arguments,
                directory: host.executableURL.deletingLastPathComponent(),
                environment: Self.environment,
                standardInput: input.fileHandleForReading.fileDescriptor,
                standardOutput: output.fileHandleForWriting.fileDescriptor,
                standardError: errorOutput.fileHandleForWriting.fileDescriptor,
            )
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errorOutput.fileHandleForReading.readabilityHandler = nil
            Logger.error("Failed to start native host \(host.name): \(error)", category: Logger.extensions)
            throw NativeMessagingError.communicationFailed
        }
        // The child holds its own copies of these ends.
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? errorOutput.fileHandleForWriting.close()
        processIdentifier = pid
        exitWatch.watch(pid)
    }

    /// Writes `message` to the host's stdin, framed. Writes happen in order off the main
    /// actor, so a host that stops reading never blocks the browser.
    ///
    /// - Throws: ``NativeMessagingError/hostExited`` after the host's output ended;
    ///   ``NativeMessageFraming/frame(_:)``'s errors for a message that cannot be sent.
    func send(_ message: Any) throws {
        guard !isOutputClosed, !isTerminated else { throw NativeMessagingError.hostExited }
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

    /// Stops the host: no more events, stdin closed, SIGTERM, and SIGKILL if it outlives
    /// ``Timing/killDelay``.
    func terminate() {
        guard !isTerminated else { return }
        isTerminated = true
        isOutputClosed = true
        output.fileHandleForReading.readabilityHandler = nil
        let handle = input.fileHandleForWriting
        writer.async {
            try? handle.close()
        }
        guard let pid = processIdentifier, !exitWatch.hasExited else { return }
        kill(pid, SIGTERM)
        let exitWatch = exitWatch
        Task(name: "Kill native host") {
            try? await Task.sleep(for: Timing.killDelay)
            if !exitWatch.hasExited {
                kill(pid, SIGKILL)
            }
        }
    }

    private func deliver(_ event: Event) {
        guard !isOutputClosed else { return }
        if case .closed = event {
            isOutputClosed = true
            onEvent(event)
            terminate()
            return
        }
        onEvent(event)
    }
}

/// Watches a host process for its exit and collects it so it leaves no zombie, also after
/// the ``NativeMessagingHostProcess`` that started it is gone.
private final class ExitWatch {
    private(set) var hasExited = false
    /// Held until the process exits.
    private var source: (any DispatchSourceProcess)?

    func watch(_ pid: pid_t) {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                self.reap(pid)
            }
        }
        self.source = source
        source.resume()
        // A process that exited before the source existed raises no event.
        reap(pid)
    }

    private func reap(_ pid: pid_t) {
        var status: Int32 = 0
        guard !hasExited, waitpid(pid, &status, WNOHANG) == pid else { return }
        hasExited = true
        source?.cancel()
        source = nil
    }
}

/// Starts a host with `posix_spawn`: only the three standard descriptors are inherited, and
/// the child is responsible for its own privacy permissions.
private nonisolated enum HostSpawner {
    private typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32

    struct SpawnError: Error {
        let code: Int32
    }

    static func spawn(
        executable: URL,
        arguments: [String],
        directory: URL,
        environment: [String: String],
        standardInput: Int32,
        standardOutput: Int32,
        standardError: Int32,
    ) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, standardInput, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, standardOutput, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, standardError, STDERR_FILENO)
        posix_spawn_file_actions_addchdir_np(&actions, directory.path)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        // The same disclaim Chrome and Firefox apply to their native hosts. RTLD_DEFAULT is -2.
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim") {
            _ = unsafeBitCast(symbol, to: SetDisclaim.self)(&attributes, 1)
        }

        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, executable.path, &actions, &attributes, argv, envp)
        guard status == 0 else { throw SpawnError(code: status) }
        return pid
    }
}

/// The host's stdout framing state, read from the file handle's serial callback queue.
private final nonisolated class FrameReader: Sendable {
    private let decoder = Mutex(NativeMessageFraming.Decoder())

    func append(_ data: Data) throws -> [Data] {
        try decoder.withLock { try $0.append(data) }
    }
}
