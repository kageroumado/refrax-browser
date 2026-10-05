import Foundation

/// Errors produced by ``HTTPClient`` operations.
nonisolated enum HTTPClientError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: Data?)
    case decodingFailed(any Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Server returned an invalid response"
        case let .httpError(statusCode, _):
            "HTTP \(statusCode)"
        case let .decodingFailed(error):
            "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

/// Lightweight HTTP client for non-WebKit networking.
///
/// Used by `FeedbackSubmissionService` and `AppUpdateChecker` for
/// API calls that don't involve web content rendering.
nonisolated enum HTTPClient: Sendable {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "\(Constants.App.name)/\(Constants.App.version)",
        ]
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Performs a GET request and decodes the JSON response.
    ///
    /// - Parameters:
    ///   - url: The endpoint URL.
    ///   - as: The expected response type.
    /// - Returns: The decoded response value.
    static func get<T: Decodable>(_ url: URL, as _: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HTTPClientError.decodingFailed(error)
        }
    }

    /// Performs a multipart/form-data upload.
    ///
    /// - Parameters:
    ///   - url: The endpoint URL.
    ///   - parts: The multipart body parts.
    /// - Returns: The raw response data.
    @discardableResult
    static func uploadMultipart(_ url: URL, parts: [MultipartPart]) async throws -> Data {
        let boundary = "Refrax-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type",
        )

        request.httpBody = buildMultipartBody(parts: parts, boundary: boundary)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    /// Performs a raw request using the configured session.
    ///
    /// Use this when you need custom headers or response handling that
    /// the typed convenience methods don't support (e.g., conditional
    /// requests with ETags).
    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    // MARK: - Private

    private static func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw HTTPClientError.httpError(statusCode: http.statusCode, body: data)
        }
    }

    private static func buildMultipartBody(parts: [MultipartPart], boundary: String) -> Data {
        var body = Data()
        let crlf = "\r\n"

        for part in parts {
            body.append("--\(boundary)\(crlf)")

            if let filename = part.filename {
                body.append(
                    "Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(filename)\"\(crlf)",
                )
            } else {
                body.append("Content-Disposition: form-data; name=\"\(part.name)\"\(crlf)")
            }

            body.append("Content-Type: \(part.contentType)\(crlf)")
            body.append(crlf)
            body.append(part.data)
            body.append(crlf)
        }

        body.append("--\(boundary)--\(crlf)")
        return body
    }
}

// MARK: - Data Convenience

private nonisolated extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
