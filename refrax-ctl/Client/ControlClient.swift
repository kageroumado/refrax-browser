import Darwin
import Foundation
import RefraxProtocol

nonisolated enum ControlClient {
    static let socketPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default

        // Try debug build first (more likely during development), then release
        let debugPath = "\(home)/Library/Application Support/website.refrax.browser.debug/ctl.sock"
        let releasePath = "\(home)/Library/Application Support/website.refrax.browser/ctl.sock"

        if fm.fileExists(atPath: debugPath) {
            return debugPath
        }
        return releasePath
    }()

    static let maxMessageBytes = 64 * 1_024 * 1_024 // 64MB
    static var timeoutSec: TimeInterval {
        TimeInterval(CLIConfig.timeout)
    }

    /// Sends a request and waits for a response (blocking).
    ///
    /// Retries on connection failures if `CLIConfig.retry > 0`.
    /// Auto-launches Refrax if not running and waits for it to become ready.
    static func send(_ request: ControlRequest) throws -> ControlResponse {
        let encoder = JSONEncoder()
        let requestData = try encoder.encode(request)
        let maxAttempts = CLIConfig.retry + 1

        var lastError: any Error = ControlClientError.notRunning
        var didAutoLaunch = false

        for attempt in 1 ... maxAttempts {
            do {
                let responseData = try sendRaw(requestData)
                let decoder = JSONDecoder()
                return try decoder.decode(ControlResponse.self, from: responseData)
            } catch ControlClientError.notRunning where !didAutoLaunch {
                didAutoLaunch = true
                lastError = ControlClientError.notRunning

                if tryLaunch() {
                    continue
                }

                if attempt < maxAttempts {
                    Thread.sleep(forTimeInterval: CLIConfig.retryDelay)
                }
            } catch let error as ControlClientError where error.isRetryable && attempt < maxAttempts {
                lastError = error
                if CLIConfig.verbose {
                    printInfo("[retry] attempt \(attempt)/\(maxAttempts) failed: \(error.localizedDescription)")
                }
                Thread.sleep(forTimeInterval: CLIConfig.retryDelay)
            } catch {
                throw error
            }
        }
        throw lastError
    }

    /// Launches Refrax and waits for the control socket to appear.
    ///
    /// Tries debug build first (for developers), then release. Polls for
    /// the socket for up to 10 seconds after a successful `open` call.
    ///
    /// - Returns: `true` if the socket becomes available.
    @discardableResult
    static func tryLaunch() -> Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let debugSocket = "\(home)/Library/Application Support/website.refrax.browser.debug/ctl.sock"
        let releaseSocket = "\(home)/Library/Application Support/website.refrax.browser/ctl.sock"

        printInfo("Refrax is not running. Launching...")

        // Try debug build first (for developers), then release
        let bundleIDs = ["website.refrax.browser.debug", "website.refrax.browser"]
        var launched = false

        for bundleID in bundleIDs {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-b", bundleID]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    launched = true
                    if CLIConfig.verbose {
                        printInfo("[launch] launched \(bundleID)")
                    }
                    break
                }
            } catch {
                continue
            }
        }

        guard launched else {
            printInfo("Could not launch Refrax. Is it installed?")
            return false
        }

        // Poll for the socket to appear (up to 10 seconds)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if fm.fileExists(atPath: debugSocket) || fm.fileExists(atPath: releaseSocket) {
                // Socket file exists — give the server a moment to start accepting
                Thread.sleep(forTimeInterval: 0.5)
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        printInfo("Refrax launched but control server did not start within 10s.")
        printInfo("Check that CLI Control is enabled in Refrax Settings > Advanced.")
        return false
    }

    /// Low-level: sends raw bytes and returns raw response bytes.
    static func sendRaw(_ data: Data) throws -> Data {
        // 1. Create socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ControlClientError.socketCreationFailed(errno)
        }
        defer { close(fd) }

        // Disable SIGPIPE
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))

        // 2. Connect
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        let copied = socketPath.withCString { cstr -> Int in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                pathPtr.withMemoryRebound(to: CChar.self, capacity: capacity) { dest in
                    strlcpy(dest, cstr, capacity)
                }
            }
        }
        guard copied < capacity else {
            throw ControlClientError.pathTooLong
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            let err = errno
            switch err {
            case ECONNREFUSED, ENOENT:
                throw ControlClientError.notRunning
            default:
                throw ControlClientError.connectFailed(err)
            }
        }

        // 3. Write request
        try writeAll(fd: fd, data: data)

        // 4. Half-close (signal end of request)
        shutdown(fd, SHUT_WR)

        // 5. Read response with timeout
        return try readAll(fd: fd, maxBytes: maxMessageBytes, timeoutSec: timeoutSec)
    }

    private static func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { buf in
            guard let base = buf.baseAddress else { return }
            var written = 0
            while written < data.count {
                let n = write(fd, base.advanced(by: written), data.count - written)
                if n > 0 {
                    written += n
                    continue
                }
                if n == -1, errno == EINTR { continue }
                throw ControlClientError.writeFailed(errno)
            }
        }
    }

    private static func readAll(fd: Int32, maxBytes: Int, timeoutSec: TimeInterval) throws -> Data {
        let deadline = Date().addingTimeInterval(timeoutSec)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1_024)

        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                throw ControlClientError.timeout
            }

            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let sliceMs = max(1.0, min(remaining, 0.25) * 1_000.0)
            let polled = poll(&pfd, 1, Int32(sliceMs))
            if polled == 0 { continue }
            if polled < 0 {
                if errno == EINTR { continue }
                throw ControlClientError.readFailed(errno)
            }

            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress!, $0.count) }
            if n > 0 {
                data.append(buffer, count: n)
                if data.count > maxBytes {
                    throw ControlClientError.responseTooLarge
                }
                continue
            }

            if n == 0 {
                return data // EOF — response complete
            }

            if errno == EINTR || errno == EAGAIN { continue }
            throw ControlClientError.readFailed(errno)
        }
    }
}

enum ControlClientError: LocalizedError {
    case socketCreationFailed(Int32)
    case pathTooLong
    case notRunning
    case connectFailed(Int32)
    case writeFailed(Int32)
    case readFailed(Int32)
    case timeout
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case let .socketCreationFailed(e): "Failed to create socket: \(String(cString: strerror(e)))"
        case .pathTooLong: "Socket path too long"
        case .notRunning: "Refrax is not running. Run `refrax-ctl launch` to start it."
        case let .connectFailed(e): "Failed to connect: \(String(cString: strerror(e)))"
        case let .writeFailed(e): "Failed to write: \(String(cString: strerror(e)))"
        case let .readFailed(e): "Failed to read: \(String(cString: strerror(e)))"
        case .timeout: "Request timed out (\(CLIConfig.timeout)s). The operation may still be in progress."
        case .responseTooLarge: "Response exceeds maximum size"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .notRunning, .connectFailed, .timeout: true
        default: false
        }
    }
}
