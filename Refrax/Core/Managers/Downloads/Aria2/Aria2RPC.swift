import Foundation

/// JSON-RPC client for communicating with aria2c daemon.
///
/// aria2c is a powerful download utility that supports:
/// - Multi-connection downloads (faster than single connection)
/// - Automatic resume of interrupted downloads
/// - Metalink and BitTorrent
///
/// ## Architecture
///
/// ```
/// ┌─────────────────┐     JSON-RPC      ┌──────────────┐
/// │     Refrax      │ ←───────────────→ │   aria2c     │
/// │   (Aria2RPC)    │   localhost:6800  │   daemon     │
/// └─────────────────┘                   └──────────────┘
/// ```
///
/// ## Usage
///
/// ```swift
/// let rpc = Aria2RPC(secret: "mytoken")
/// let gid = try await rpc.addUri(["https://example.com/file.zip"])
/// let status = try await rpc.tellStatus(gid: gid)
/// ```
actor Aria2RPC {
    // MARK: - Types

    /// Error types for aria2 RPC operations.
    enum Error: Swift.Error, LocalizedError {
        case httpError(statusCode: Int)
        case rpcError(code: Int, message: String)
        case invalidResponse
        case connectionFailed(any Swift.Error)
        case notRunning

        var errorDescription: String? {
            switch self {
            case let .httpError(code):
                "HTTP error: \(code)"
            case let .rpcError(code, message):
                "aria2 error (\(code)): \(message)"
            case .invalidResponse:
                "Invalid response from aria2"
            case let .connectionFailed(error):
                "Connection failed: \(error.localizedDescription)"
            case .notRunning:
                "aria2 daemon is not running"
            }
        }
    }

    /// Download status returned by aria2.
    struct DownloadStatus: Sendable {
        let gid: String
        let status: Status
        let totalLength: Int64
        let completedLength: Int64
        let downloadSpeed: Int64
        let uploadSpeed: Int64
        let connections: Int
        let errorCode: Int?
        let errorMessage: String?
        let files: [FileInfo]

        enum Status: String, Sendable {
            case active
            case waiting
            case paused
            case error
            case complete
            case removed
        }

        struct FileInfo: Sendable {
            let index: Int
            let path: String
            let length: Int64
            let completedLength: Int64
            let selected: Bool
        }

        var progress: Double {
            guard totalLength > 0 else { return 0 }
            return Double(completedLength) / Double(totalLength)
        }

        var isComplete: Bool {
            status == .complete
        }

        var hasFailed: Bool {
            status == .error
        }
    }

    /// Global statistics from aria2.
    struct GlobalStats: Sendable {
        let downloadSpeed: Int64
        let uploadSpeed: Int64
        let numActive: Int
        let numWaiting: Int
        let numStopped: Int
        let numStoppedTotal: Int
    }

    // MARK: - Properties

    private let baseURL: URL
    private let secret: String
    private var requestID = 0
    private let session: URLSession

    // MARK: - Initialization

    /// Creates an aria2 RPC client.
    ///
    /// - Parameters:
    ///   - host: RPC server host (default: localhost).
    ///   - port: RPC server port (default: 6800).
    ///   - secret: RPC secret token for authentication.
    init(host: String = "localhost", port: Int = 6_800, secret: String) {
        if let url = URL(string: "http://\(host):\(port)/jsonrpc") {
            self.baseURL = url
        } else {
            Logger.warning(
                "Malformed aria2 RPC host/port combination (\(host):\(port)), falling back to localhost:6800",
                category: Logger.downloads,
            )
            self.baseURL = URL.staticRequired("http://localhost:6800/jsonrpc")
        }
        self.secret = secret

        // Create session with short timeout for local daemon
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Download Management

    /// Adds a new download.
    ///
    /// - Parameters:
    ///   - uris: Array of URLs (mirrors) for the same resource.
    ///   - options: Download options (headers, output path, etc.).
    ///   - position: Queue position (nil = end of queue).
    /// - Returns: GID (Global ID) of the new download.
    func addUri(
        _ uris: [String],
        options: [String: Any] = [:],
        position: Int? = nil,
    ) async throws -> String {
        var params: [Any] = [uris, options]
        if let position {
            params.append(position)
        }

        let result = try await sendRequest(method: "aria2.addUri", params: params)
        guard let gid = result as? String else {
            throw Error.invalidResponse
        }
        return gid
    }

    /// Removes a download.
    ///
    /// - Parameter gid: The download GID.
    /// - Returns: The removed GID.
    @discardableResult
    func remove(gid: String) async throws -> String {
        let result = try await sendRequest(method: "aria2.remove", params: [gid])
        return result as? String ?? gid
    }

    /// Force removes a download (doesn't wait for completion).
    @discardableResult
    func forceRemove(gid: String) async throws -> String {
        let result = try await sendRequest(method: "aria2.forceRemove", params: [gid])
        return result as? String ?? gid
    }

    /// Pauses a download.
    @discardableResult
    func pause(gid: String) async throws -> String {
        let result = try await sendRequest(method: "aria2.pause", params: [gid])
        return result as? String ?? gid
    }

    /// Pauses all downloads.
    func pauseAll() async throws {
        _ = try await sendRequest(method: "aria2.pauseAll", params: [])
    }

    /// Resumes a paused download.
    @discardableResult
    func unpause(gid: String) async throws -> String {
        let result = try await sendRequest(method: "aria2.unpause", params: [gid])
        return result as? String ?? gid
    }

    /// Resumes all paused downloads.
    func unpauseAll() async throws {
        _ = try await sendRequest(method: "aria2.unpauseAll", params: [])
    }

    // MARK: - Status Queries

    /// Gets the status of a download.
    ///
    /// - Parameters:
    ///   - gid: The download GID.
    ///   - keys: Specific keys to retrieve (nil = all).
    /// - Returns: Download status.
    func tellStatus(gid: String, keys: [String]? = nil) async throws -> DownloadStatus {
        var params: [Any] = [gid]
        if let keys {
            params.append(keys)
        }

        let result = try await sendRequest(method: "aria2.tellStatus", params: params)
        guard let dict = result as? [String: Any] else {
            throw Error.invalidResponse
        }

        return parseDownloadStatus(dict)
    }

    /// Gets all active downloads.
    func tellActive(keys: [String]? = nil) async throws -> [DownloadStatus] {
        var params: [Any] = []
        if let keys {
            params.append(keys)
        }

        let result = try await sendRequest(method: "aria2.tellActive", params: params)
        guard let array = result as? [[String: Any]] else {
            throw Error.invalidResponse
        }

        return array.map { parseDownloadStatus($0) }
    }

    /// Gets waiting downloads.
    func tellWaiting(offset: Int = 0, num: Int = 100, keys: [String]? = nil) async throws -> [DownloadStatus] {
        var params: [Any] = [offset, num]
        if let keys {
            params.append(keys)
        }

        let result = try await sendRequest(method: "aria2.tellWaiting", params: params)
        guard let array = result as? [[String: Any]] else {
            throw Error.invalidResponse
        }

        return array.map { parseDownloadStatus($0) }
    }

    /// Gets stopped (completed/error) downloads.
    func tellStopped(offset: Int = 0, num: Int = 100, keys: [String]? = nil) async throws -> [DownloadStatus] {
        var params: [Any] = [offset, num]
        if let keys {
            params.append(keys)
        }

        let result = try await sendRequest(method: "aria2.tellStopped", params: params)
        guard let array = result as? [[String: Any]] else {
            throw Error.invalidResponse
        }

        return array.map { parseDownloadStatus($0) }
    }

    /// Gets global statistics.
    func getGlobalStat() async throws -> GlobalStats {
        let result = try await sendRequest(method: "aria2.getGlobalStat", params: [])
        guard let dict = result as? [String: Any] else {
            throw Error.invalidResponse
        }

        return GlobalStats(
            downloadSpeed: Int64(dict["downloadSpeed"] as? String ?? "0") ?? 0,
            uploadSpeed: Int64(dict["uploadSpeed"] as? String ?? "0") ?? 0,
            numActive: Int(dict["numActive"] as? String ?? "0") ?? 0,
            numWaiting: Int(dict["numWaiting"] as? String ?? "0") ?? 0,
            numStopped: Int(dict["numStopped"] as? String ?? "0") ?? 0,
            numStoppedTotal: Int(dict["numStoppedTotal"] as? String ?? "0") ?? 0,
        )
    }

    // MARK: - Session Management

    /// Gets aria2 version info.
    func getVersion() async throws -> (version: String, features: [String]) {
        let result = try await sendRequest(method: "aria2.getVersion", params: [])
        guard let dict = result as? [String: Any],
              let version = dict["version"] as? String else {
            throw Error.invalidResponse
        }

        let features = dict["enabledFeatures"] as? [String] ?? []
        return (version, features)
    }

    /// Shuts down aria2 daemon.
    func shutdown() async throws {
        _ = try await sendRequest(method: "aria2.shutdown", params: [])
    }

    // MARK: - BitTorrent

    /// Adds a magnet link download.
    ///
    /// Magnet links are handled by aria2's `addUri` since magnet: is a URI scheme.
    ///
    /// - Parameters:
    ///   - magnetURI: The magnet: URI string.
    ///   - options: Download options (output dir, etc.).
    /// - Returns: GID of the new download.
    func addMagnet(_ magnetURI: String, options: [String: Any] = [:]) async throws -> String {
        // aria2 treats magnet: as a regular URI
        try await addUri([magnetURI], options: options)
    }

    /// Adds a torrent download from base64-encoded .torrent file data.
    ///
    /// - Parameters:
    ///   - torrentData: Base64-encoded contents of a .torrent file.
    ///   - options: Download options (output dir, etc.).
    /// - Returns: GID of the new download.
    func addTorrent(_ torrentData: String, options: [String: Any] = [:]) async throws -> String {
        let result = try await sendRequest(method: "aria2.addTorrent", params: [torrentData, [], options])
        guard let gid = result as? String else {
            throw Error.invalidResponse
        }
        return gid
    }

    /// Gets BitTorrent-specific status for a download.
    ///
    /// - Parameter gid: The download GID.
    /// - Returns: BitTorrent status info, or nil if not a BitTorrent download.
    func getBtStatus(gid: String) async throws -> BtStatus? {
        let result = try await sendRequest(
            method: "aria2.tellStatus",
            params: [gid, ["bittorrent", "numSeeders", "numPieces", "pieceLength", "connections"]],
        )
        guard let dict = result as? [String: Any] else {
            throw Error.invalidResponse
        }

        // Check if this is a BitTorrent download
        guard let btInfo = dict["bittorrent"] as? [String: Any] else {
            return nil
        }

        let info = btInfo["info"] as? [String: Any]
        return BtStatus(
            name: info?["name"] as? String,
            numSeeders: Int(dict["numSeeders"] as? String ?? "0") ?? 0,
            numPeers: Int(dict["connections"] as? String ?? "0") ?? 0,
        )
    }

    /// BitTorrent-specific status information.
    struct BtStatus: Sendable {
        /// Torrent name from metadata.
        let name: String?
        /// Number of seeders connected.
        let numSeeders: Int
        /// Number of peers connected.
        let numPeers: Int
    }

    /// Force shuts down aria2 daemon.
    func forceShutdown() async throws {
        _ = try await sendRequest(method: "aria2.forceShutdown", params: [])
    }

    /// Checks if aria2 daemon is running.
    func isRunning() async -> Bool {
        do {
            _ = try await getVersion()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private Implementation

    private func sendRequest(method: String, params: [Any]) async throws -> Any {
        requestID += 1

        // Prepend secret token to params
        var finalParams: [Any] = ["token:\(secret)"]
        finalParams.append(contentsOf: params)

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method,
            "params": finalParams,
        ]

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Error.connectionFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw Error.httpError(statusCode: httpResponse.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Error.invalidResponse
        }

        // Check for RPC error
        if let error = json["error"] as? [String: Any],
           let code = error["code"] as? Int,
           let message = error["message"] as? String {
            throw Error.rpcError(code: code, message: message)
        }

        guard let result = json["result"] else {
            throw Error.invalidResponse
        }

        return result
    }

    private func parseDownloadStatus(_ dict: [String: Any]) -> DownloadStatus {
        let files = (dict["files"] as? [[String: Any]])?.enumerated().map { index, fileDict in
            DownloadStatus.FileInfo(
                index: Int(fileDict["index"] as? String ?? "\(index)") ?? index,
                path: fileDict["path"] as? String ?? "",
                length: Int64(fileDict["length"] as? String ?? "0") ?? 0,
                completedLength: Int64(fileDict["completedLength"] as? String ?? "0") ?? 0,
                selected: fileDict["selected"] as? String == "true",
            )
        } ?? []

        return DownloadStatus(
            gid: dict["gid"] as? String ?? "",
            status: DownloadStatus.Status(rawValue: dict["status"] as? String ?? "") ?? .error,
            totalLength: Int64(dict["totalLength"] as? String ?? "0") ?? 0,
            completedLength: Int64(dict["completedLength"] as? String ?? "0") ?? 0,
            downloadSpeed: Int64(dict["downloadSpeed"] as? String ?? "0") ?? 0,
            uploadSpeed: Int64(dict["uploadSpeed"] as? String ?? "0") ?? 0,
            connections: Int(dict["connections"] as? String ?? "0") ?? 0,
            errorCode: (dict["errorCode"] as? String).flatMap { Int($0) },
            errorMessage: dict["errorMessage"] as? String,
            files: files,
        )
    }
}

// MARK: - Download Options Builder

extension Aria2RPC {
    /// Builds download options dictionary for aria2.
    struct DownloadOptions {
        private var options: [String: Any] = [:]

        /// Creates empty options.
        init() {}

        /// Sets custom HTTP headers.
        ///
        /// Note: This appends to existing headers, so it can be combined with
        /// `setCookies`, `setUserAgent`, etc.
        mutating func setHeaders(_ headers: [String: String]) -> Self {
            var existingHeaders = options["header"] as? [String] ?? []
            existingHeaders.append(contentsOf: headers.map { "\($0.key): \($0.value)" })
            options["header"] = existingHeaders
            return self
        }

        /// Sets cookie header.
        mutating func setCookies(_ cookies: String) -> Self {
            var headers = options["header"] as? [String] ?? []
            headers.append("Cookie: \(cookies)")
            options["header"] = headers
            return self
        }

        /// Sets User-Agent header.
        mutating func setUserAgent(_ userAgent: String) -> Self {
            var headers = options["header"] as? [String] ?? []
            headers.append("User-Agent: \(userAgent)")
            options["header"] = headers
            return self
        }

        /// Sets referer header.
        mutating func setReferer(_ referer: String) -> Self {
            options["referer"] = referer
            return self
        }

        /// Sets output directory.
        mutating func setDirectory(_ path: String) -> Self {
            options["dir"] = path
            return self
        }

        /// Sets output filename.
        mutating func setFilename(_ filename: String) -> Self {
            options["out"] = filename
            return self
        }

        /// Enables multi-connection download.
        mutating func setConnections(_ count: Int) -> Self {
            options["split"] = String(count)
            options["max-connection-per-server"] = String(count)
            return self
        }

        /// Enables resume.
        mutating func enableResume(_ enable: Bool = true) -> Self {
            options["continue"] = enable ? "true" : "false"
            return self
        }

        /// Converts to dictionary for RPC call.
        func build() -> [String: Any] {
            options
        }
    }
}
