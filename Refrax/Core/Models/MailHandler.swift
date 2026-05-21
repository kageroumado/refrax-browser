import AppKit
import Foundation

/// Preferred handler for mailto: links.
///
/// Users can choose to open email links in the system mail app or redirect
/// to a web mail service. This enum provides URL building for each service.
///
/// ## Supported Services
///
/// - **System Default**: Opens in Mail.app or user's configured mail app
/// - **Gmail**: Opens Gmail compose in browser
/// - **Outlook**: Opens Outlook.com compose in browser
/// - **Yahoo Mail**: Opens Yahoo Mail compose in browser
/// - **ProtonMail**: Opens ProtonMail compose in browser
/// - **Fastmail**: Opens Fastmail compose in browser
///
/// ## Usage
///
/// ```swift
/// let handler = MailHandler.gmail
/// if let webURL = handler.buildComposeURL(from: mailtoURL) {
///     // Open webURL in new tab
/// }
/// ```
enum MailHandler: String, Codable, CaseIterable, Sendable {
    case system
    case gmail
    case outlook
    case yahoo
    case proton
    case fastmail

    // MARK: - Display Properties

    /// User-visible name for the handler.
    var displayName: String {
        switch self {
        case .system: "System Default"
        case .gmail: "Gmail"
        case .outlook: "Outlook"
        case .yahoo: "Yahoo Mail"
        case .proton: "ProtonMail"
        case .fastmail: "Fastmail"
        }
    }

    /// Short description of what the handler does.
    var displayDescription: String {
        switch self {
        case .system: "Opens in your default mail app."
        case .gmail: "Opens Gmail compose in browser."
        case .outlook: "Opens Outlook.com compose in browser."
        case .yahoo: "Opens Yahoo Mail compose in browser."
        case .proton: "Opens ProtonMail compose in browser."
        case .fastmail: "Opens Fastmail compose in browser."
        }
    }

    /// SF Symbol name for the handler.
    var iconName: String {
        switch self {
        case .system: "envelope.fill"
        case .gmail: "envelope.fill"
        case .outlook: "envelope.fill"
        case .yahoo: "envelope.fill"
        case .proton: "lock.shield.fill"
        case .fastmail: "envelope.fill"
        }
    }

    // MARK: - Default Mail App Detection

    /// Returns the name of the system's default mail app, or "Mail" if unknown.
    ///
    /// - Note: Queries `NSWorkspace` on each access. Cache the result if called in a tight loop.
    static var defaultMailAppName: String {
        guard let mailtoURL = URL(string: "mailto:"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: mailtoURL)
        else {
            return "Mail"
        }
        return appURL.deletingPathExtension().lastPathComponent
    }

    /// Returns the icon of the system's default mail app.
    ///
    /// - Note: Queries `NSWorkspace` on each access. Cache the result if called in a tight loop.
    static var defaultMailAppIcon: NSImage? {
        guard let mailtoURL = URL(string: "mailto:"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: mailtoURL)
        else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    // MARK: - URL Building

    /// Base URL for the compose endpoint.
    private var composeBaseURL: String? {
        switch self {
        case .system: nil
        case .gmail: "https://mail.google.com/mail/?view=cm"
        case .outlook: "https://outlook.live.com/mail/0/deeplink/compose"
        case .yahoo: "https://compose.mail.yahoo.com/"
        case .proton: "https://mail.proton.me/u/0/compose"
        case .fastmail: "https://app.fastmail.com/mail/compose"
        }
    }

    /// Builds a web compose URL from a mailto: URL.
    ///
    /// Parses the mailto: URL and translates parameters to the service's
    /// expected format.
    ///
    /// - Parameter mailto: The original mailto: URL.
    /// - Returns: A web compose URL, or `nil` for system handler.
    func buildComposeURL(from mailto: URL) -> URL? {
        guard self != .system, let baseURL = composeBaseURL else {
            return nil
        }

        guard var components = URLComponents(string: baseURL) else {
            return nil
        }

        // Parse mailto: URL
        let parsed = parseMailto(mailto)

        // Build query items for this service
        var params = components.queryItems ?? []

        if let to = parsed.to, !to.isEmpty {
            params.append(URLQueryItem(name: paramName(for: .to), value: to))
        }
        if let cc = parsed.cc {
            params.append(URLQueryItem(name: paramName(for: .cc), value: cc))
        }
        if let bcc = parsed.bcc {
            params.append(URLQueryItem(name: paramName(for: .bcc), value: bcc))
        }
        if let subject = parsed.subject {
            params.append(URLQueryItem(name: paramName(for: .subject), value: subject))
        }
        if let body = parsed.body {
            params.append(URLQueryItem(name: paramName(for: .body), value: body))
        }

        components.queryItems = params.isEmpty ? nil : params
        return components.url
    }

    // MARK: - Mailto Parsing

    /// Parsed mailto: URL components.
    private struct MailtoComponents {
        var to: String?
        var cc: String?
        var bcc: String?
        var subject: String?
        var body: String?
    }

    /// Parses a mailto: URL into its components.
    ///
    /// Handles both simple (`mailto:user@example.com`) and complex
    /// (`mailto:user@example.com?subject=Hello&body=Hi`) formats.
    private func parseMailto(_ url: URL) -> MailtoComponents {
        var result = MailtoComponents()

        let urlString = url.absoluteString

        // Remove "mailto:" prefix
        guard urlString.lowercased().hasPrefix("mailto:") else {
            return result
        }

        let afterScheme = String(urlString.dropFirst(7))

        // Split into recipients and query string
        if let questionIndex = afterScheme.firstIndex(of: "?") {
            let recipients = String(afterScheme[..<questionIndex])
            let queryString = String(afterScheme[afterScheme.index(after: questionIndex)...])

            result.to = recipients.removingPercentEncoding

            // Parse query parameters
            let pairs = queryString.split(separator: "&")
            for pair in pairs {
                let keyValue = pair.split(separator: "=", maxSplits: 1)
                guard keyValue.count >= 1 else { continue }

                let key = String(keyValue[0]).lowercased()
                let value = keyValue.count > 1
                    ? String(keyValue[1]).removingPercentEncoding ?? ""
                    : ""

                switch key {
                case "to":
                    // Append to existing recipients
                    if let existing = result.to, !existing.isEmpty {
                        result.to = "\(existing),\(value)"
                    } else {
                        result.to = value
                    }
                case "cc": result.cc = value
                case "bcc": result.bcc = value
                case "subject": result.subject = value
                case "body": result.body = value
                default: break
                }
            }
        } else {
            // Just recipients, no query string
            result.to = afterScheme.removingPercentEncoding
        }

        return result
    }

    // MARK: - Service-Specific Parameter Names

    /// Mail parameter types.
    private enum MailParam {
        case to
        case cc
        case bcc
        case subject
        case body
    }

    /// Returns the query parameter name for a mail field on this service.
    private func paramName(for param: MailParam) -> String {
        switch (self, param) {
        case (.gmail, .to): "to"
        case (.gmail, .cc): "cc"
        case (.gmail, .bcc): "bcc"
        case (.gmail, .subject): "su"
        case (.gmail, .body): "body"
        case (.outlook, .to): "to"
        case (.outlook, .cc): "cc"
        case (.outlook, .bcc): "bcc"
        case (.outlook, .subject): "subject"
        case (.outlook, .body): "body"
        case (.yahoo, .to): "to"
        case (.yahoo, .cc): "cc"
        case (.yahoo, .bcc): "bcc"
        case (.yahoo, .subject): "subject"
        case (.yahoo, .body): "body"
        case (.proton, .to): "to"
        case (.proton, .cc): "cc"
        case (.proton, .bcc): "bcc"
        case (.proton, .subject): "subject"
        case (.proton, .body): "body"
        case (.fastmail, .to): "to"
        case (.fastmail, .cc): "cc"
        case (.fastmail, .bcc): "bcc"
        case (.fastmail, .subject): "subject"
        case (.fastmail, .body): "body"
        case (.system, .to): "to"
        case (.system, .cc): "cc"
        case (.system, .bcc): "bcc"
        case (.system, .subject): "subject"
        case (.system, .body): "body"
        }
    }
}
