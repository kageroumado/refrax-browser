import Foundation

/// Internal deep link routing for native views rendered in-tab.
///
/// Used for interstitial pages that need native SwiftUI rendering:
/// - SSL certificate errors with bypass options
/// - Focus mode blocked page interstitials
enum DeepLink: Equatable {
    case sslError(error: SSLErrorType, failedURL: URL)
    case focusBlocked(blockedURL: URL, focusName: String)

    /// The URL scheme for Refrax deep links
    static let scheme = "refrax"

    /// Create a deep link from a URL
    init?(url: URL) {
        guard url.scheme == DeepLink.scheme else { return nil }

        switch url.host {
        case "ssl-error":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            guard let typeString = components?.queryItems?.first(where: { $0.name == "type" })?.value,
                  let errorType = SSLErrorType(rawValue: typeString),
                  let urlString = components?.queryItems?.first(where: { $0.name == "url" })?.value,
                  let failedURL = URL(string: urlString)
            else {
                return nil
            }
            self = .sslError(error: errorType, failedURL: failedURL)
        case "focus-blocked":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            guard let urlString = components?.queryItems?.first(where: { $0.name == "url" })?.value,
                  let blockedURL = URL(string: urlString),
                  let focusName = components?.queryItems?.first(where: { $0.name == "focus" })?.value
            else {
                return nil
            }
            self = .focusBlocked(blockedURL: blockedURL, focusName: focusName)
        default:
            return nil
        }
    }

    /// Convert to URL.
    var url: URL {
        switch self {
        case let .sslError(error, failedURL):
            var components = URLComponents()
            components.scheme = DeepLink.scheme
            components.host = "ssl-error"
            components.queryItems = [
                URLQueryItem(name: "type", value: error.rawValue),
                URLQueryItem(name: "url", value: failedURL.absoluteString),
            ]
            return components.resolvedRequired("DeepLink.sslError")
        case let .focusBlocked(blockedURL, focusName):
            var components = URLComponents()
            components.scheme = DeepLink.scheme
            components.host = "focus-blocked"
            components.queryItems = [
                URLQueryItem(name: "url", value: blockedURL.absoluteString),
                URLQueryItem(name: "focus", value: focusName),
            ]
            return components.resolvedRequired("DeepLink.focusBlocked")
        }
    }

    /// Display title
    var title: String {
        switch self {
        case .sslError:
            "Security Warning"
        case .focusBlocked:
            "Focus Mode"
        }
    }
}

// MARK: - SSL Error Types

/// Types of SSL/TLS certificate errors for deep link routing.
///
/// These map to ``CertificateInfo.TrustError`` but are serializable
/// for URL encoding in deep links.
enum SSLErrorType: String, Equatable, Sendable {
    case expired
    case notYetValid
    case hostnameMismatch
    case selfSigned
    case revoked
    case untrustedRoot
    case unknown

    /// Creates an SSL error type from a certificate trust error.
    init(from trustError: CertificateInfo.TrustError) {
        switch trustError {
        case .expired:
            self = .expired
        case .notYetValid:
            self = .notYetValid
        case .hostnameMismatch:
            self = .hostnameMismatch
        case .selfSigned:
            self = .selfSigned
        case .revoked:
            self = .revoked
        case .untrustedRoot:
            self = .untrustedRoot
        case .trustFailure:
            self = .unknown
        }
    }

    /// User-friendly title for this error type.
    var title: String {
        switch self {
        case .expired:
            "Certificate Expired"
        case .notYetValid:
            "Certificate Not Yet Valid"
        case .hostnameMismatch:
            "Certificate Name Mismatch"
        case .selfSigned:
            "Self-Signed Certificate"
        case .revoked:
            "Certificate Revoked"
        case .untrustedRoot:
            "Untrusted Certificate Authority"
        case .unknown:
            "Certificate Error"
        }
    }

    /// Detailed description of the error.
    var description: String {
        switch self {
        case .expired:
            "The website's security certificate has expired. This may indicate the site is no longer maintained or has a configuration issue."
        case .notYetValid:
            "The website's security certificate isn't valid yet. This could mean your device's date/time is incorrect, or the site has a misconfigured certificate."
        case .hostnameMismatch:
            "The security certificate was issued for a different website. This could indicate a misconfiguration or a potential security threat."
        case .selfSigned:
            // swiftlint:disable:next line_length
            "The website is using a self-signed certificate that hasn't been verified by a trusted certificate authority. This is common for development servers but unusual for production websites."
        case .revoked:
            "The certificate authority has revoked this certificate, possibly due to a security compromise. Proceeding is not recommended."
        case .untrustedRoot:
            "The certificate was issued by an authority that isn't trusted by your system. This could be a private CA or an untrusted issuer."
        case .unknown:
            "The system could not verify this certificate. This may indicate a configuration issue or security problem."
        }
    }

    /// Icon name for this error type.
    var iconName: String {
        switch self {
        case .expired:
            "clock.badge.exclamationmark"
        case .notYetValid:
            "clock.badge.questionmark"
        case .hostnameMismatch:
            "exclamationmark.triangle"
        case .selfSigned:
            "signature"
        case .revoked:
            "xmark.seal"
        case .untrustedRoot:
            "building.columns"
        case .unknown:
            "questionmark.circle"
        }
    }

    /// Whether bypass should be allowed for this error type.
    ///
    /// Revoked certificates should never be bypassed as they may indicate
    /// a compromised certificate.
    var allowsBypass: Bool {
        switch self {
        case .revoked:
            false
        default:
            true
        }
    }
}
