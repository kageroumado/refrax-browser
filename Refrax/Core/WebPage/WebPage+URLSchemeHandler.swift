import Foundation
import WebKit

// MARK: - URL Scheme

/// A type representing a valid URL scheme.
///
/// Scheme names are case sensitive, must start with an ASCII letter, and may contain only ASCII letters,
/// numbers, the "+" character, the "-" character, and the "." character.
struct URLScheme: Hashable, Sendable {
    /// Creates a new `URLScheme` value from a valid scheme, which WebKit does not already handle.
    ///
    /// - Parameter rawValue: The raw value of the scheme string; if this is an invalid scheme,
    ///   or if WebKit already handles this scheme, the initializer returns `nil`.
    @MainActor
    init?(_ rawValue: String) {
        guard WKWebView.handlesURLScheme(rawValue) == false else {
            return nil
        }
        // Validate scheme format: must start with letter, contain only letters, digits, +, -, .
        let validCharacters = CharacterSet.letters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "+-."))
        guard let first = rawValue.unicodeScalars.first,
              CharacterSet.letters.contains(first),
              rawValue.unicodeScalars.allSatisfy({ validCharacters.contains($0) }) else {
            return nil
        }
        self.rawValue = rawValue
    }

    /// The raw value of the scheme string.
    let rawValue: String
}

// MARK: - URL Scheme Task Result

/// A value used as part of a sequence of results from a ``URLSchemeHandler``.
enum URLSchemeTaskResult: Sendable {
    /// The response to return to WebKit. The response value must include the MIME type of the request resource.
    ///
    /// This value is used to provide WebKit with the MIME type of the requested resource and its expected
    /// size. This must be added to the task result sequence at least once, but may be added multiple times
    /// if needed. It must be added to the sequence before any data values are.
    case response(URLResponse)

    /// Data for the resource. This value may contain all of the data or only some of it.
    ///
    /// If you load the data incrementally, multiple of these values may be added to the result sequence to deliver
    /// each new portion of data. Each time some new Data is added to the sequence, WebKit appends the data to any
    /// previously received data.
    ///
    /// A ``URLSchemeTaskResult/response(_:)`` must have been added to the sequence prior to any data being added to it.
    case data(Data)
}

// MARK: - URL Scheme Handler Protocol

/// A protocol for loading resources with URL schemes that WebKit doesn't handle.
///
/// Adopt the `URLSchemeHandler` protocol in types that handle custom URL schemes for your web content.
/// Custom schemes let you integrate custom resource types into your web content.
///
/// ## Example
///
/// ```swift
/// final class MySchemeHandler: URLSchemeHandler {
///     func reply(for request: URLRequest) -> some AsyncSequence<URLSchemeTaskResult, any Error> {
///         AsyncThrowingStream { continuation in
///             guard let url = request.url else {
///                 continuation.finish(throwing: URLError(.badURL))
///                 return
///             }
///
///             let response = URLResponse(
///                 url: url,
///                 mimeType: "text/html",
///                 expectedContentLength: 0,
///                 textEncodingName: "utf-8"
///             )
///
///             continuation.yield(.response(response))
///             continuation.yield(.data(Data()))
///             continuation.finish()
///         }
///     }
/// }
/// ```
protocol URLSchemeHandler {
    /// The type of sequence produced by the handler.
    associatedtype TaskSequence: AsyncSequence<URLSchemeTaskResult, any Error>

    /// Produces a sequence of intermixed responses and data to load a resource for a given request.
    ///
    /// Upon receiving the request, add a ``URLSchemeTaskResult/response(_:)`` value to the async sequence.
    /// After loading resource data, add ``URLSchemeTaskResult/data(_:)`` values.
    func reply(for request: URLRequest) -> TaskSequence
}

// MARK: - URL Scheme Handler Adapter

/// Adapts a ``URLSchemeHandler`` to `WKURLSchemeHandler`.
final class URLSchemeHandlerAdapter: NSObject, WKURLSchemeHandler {
    init(_ wrapped: any URLSchemeHandler) {
        self.wrapped = wrapped
    }

    private let wrapped: any URLSchemeHandler
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    func webView(_: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let task = Task {
            do {
                for try await result in wrapped.reply(for: urlSchemeTask.request) {
                    try Task.checkCancellation()

                    switch result {
                    case let .response(response):
                        urlSchemeTask.didReceive(response)

                    case let .data(data):
                        urlSchemeTask.didReceive(data)
                    }
                }

                try Task.checkCancellation()
                urlSchemeTask.didFinish()
            } catch is CancellationError {
                // Task was cancelled - the scheme task has already been stopped
            } catch {
                urlSchemeTask.didFailWithError(error)
            }

            tasks[ObjectIdentifier(urlSchemeTask)] = nil
        }

        tasks[ObjectIdentifier(urlSchemeTask)] = task
    }

    func webView(_: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }
}
