import CryptoKit
import Foundation
import Security

// MARK: - Certificate Trust Information

/// Information about a website's SSL/TLS certificate.
///
/// Provides details about the security certificate of a webpage, including its
/// validity, issuer, and any trust issues. Displayed in the address bar to help
/// users make informed decisions about website security.
///
/// ## Trust States
///
/// - **Valid**: Certificate is trusted and verified by a known Certificate Authority
/// - **Invalid**: Certificate has issues (expired, wrong domain, self-signed, etc.)
/// - **Unknown**: Certificate could not be evaluated (no HTTPS or evaluation failed)
///
/// ## References
///
/// - [Evaluating Trust and Parsing Results](https://developer.apple.com/documentation/security/certificate_key_and_trust_services/trust/evaluating_a_trust_and_parsing_the_result)
/// - [SecTrustEvaluateWithError](https://developer.apple.com/documentation/security/2980705-sectrustevaluatewitherror)
/// - [Certificate Requirements for iOS 13+/macOS 10.15+](https://support.apple.com/en-us/103769)
nonisolated struct CertificateInfo: Sendable, Equatable {
    /// The trust state of this certificate.
    let trustState: TrustState

    /// The subject common name (usually the domain name).
    let subjectName: String?

    /// The organization that owns the certificate.
    let organization: String?

    /// The certificate authority that issued this certificate.
    let issuer: String?

    /// When the certificate becomes valid.
    let validFrom: Date?

    /// When the certificate expires.
    let validUntil: Date?

    /// SHA-256 fingerprint of the certificate.
    let fingerprint: String?

    /// The full certificate chain from leaf to root.
    let certificateChain: [CertificateChainEntry]

    /// Whether the connection is secure (valid certificate).
    var isSecure: Bool {
        trustState == .valid
    }

    /// Creates certificate info for a non-HTTPS connection.
    static let insecure = CertificateInfo(
        trustState: .unknown,
        subjectName: nil,
        organization: nil,
        issuer: nil,
        validFrom: nil,
        validUntil: nil,
        fingerprint: nil,
        certificateChain: [],
    )
}

// MARK: - Certificate Chain Entry

nonisolated extension CertificateInfo {
    /// An entry in the certificate chain.
    ///
    /// Represents a single certificate in the trust chain, from the leaf (server)
    /// certificate up through intermediates to the root CA.
    struct CertificateChainEntry: Sendable, Equatable, Identifiable {
        let id: UUID

        /// The certificate's subject summary (typically the CN or organization).
        let summary: String

        /// The common name from the certificate.
        let commonName: String?

        /// The organization from the certificate.
        let organization: String?

        /// SHA-256 fingerprint of this certificate.
        let fingerprint: String

        /// Whether this is the leaf (server) certificate.
        let isLeaf: Bool

        /// Whether this is a root CA certificate (self-issued).
        let isRoot: Bool

        init(
            summary: String,
            commonName: String?,
            organization: String?,
            fingerprint: String,
            isLeaf: Bool,
            isRoot: Bool,
        ) {
            self.id = UUID()
            self.summary = summary
            self.commonName = commonName
            self.organization = organization
            self.fingerprint = fingerprint
            self.isLeaf = isLeaf
            self.isRoot = isRoot
        }
    }
}

// MARK: - Trust State

nonisolated extension CertificateInfo {
    /// The trust state of a certificate.
    enum TrustState: Sendable, Equatable {
        /// Certificate is valid and trusted.
        case valid

        /// Certificate is invalid or untrusted.
        case invalid(TrustError)

        /// Certificate could not be evaluated.
        case unknown
    }

    /// Specific reasons why a certificate might be untrusted.
    ///
    /// Maps to Security framework error codes per Apple's documentation.
    /// See: https://developer.apple.com/documentation/security/1542001-security_framework_result_codes
    enum TrustError: Sendable, Equatable {
        /// Certificate has passed its expiration date.
        case expired

        /// Certificate's "not before" date is in the future.
        case notYetValid

        /// Certificate's common name doesn't match the requested hostname.
        case hostnameMismatch

        /// Certificate is self-signed (issuer equals subject).
        case selfSigned

        /// Certificate has been revoked by its issuing CA.
        case revoked

        /// Root CA is not in the system trust store.
        case untrustedRoot

        /// Generic trust failure with the underlying OSStatus code.
        case trustFailure(OSStatus)

        /// User-friendly description of the error.
        var localizedDescription: String {
            switch self {
            case .expired:
                "The certificate has expired"
            case .notYetValid:
                "The certificate is not yet valid"
            case .hostnameMismatch:
                "The certificate doesn't match this website"
            case .selfSigned:
                "The certificate is self-signed"
            case .revoked:
                "The certificate has been revoked"
            case .untrustedRoot:
                "The certificate authority is not trusted"
            case let .trustFailure(status):
                "Certificate verification failed (error \(status))"
            }
        }

        /// Detailed explanation for error pages.
        var detailedDescription: String {
            switch self {
            case .expired:
                "The website's security certificate has expired. This may indicate the site is no longer maintained or there's a configuration issue."
            case .notYetValid:
                "The website's security certificate isn't valid yet. This could mean your device's date/time is incorrect, or the site has a misconfigured certificate."
            case .hostnameMismatch:
                "The security certificate was issued for a different website. This could indicate a misconfiguration or a potential security threat."
            case .selfSigned:
                // swiftlint:disable:next line_length
                "The website is using a self-signed certificate that hasn't been verified by a trusted certificate authority. This is common for development servers but unusual for production websites."
            case .revoked:
                "The certificate authority has revoked this certificate, possibly due to a security compromise. You should not proceed."
            case .untrustedRoot:
                "The certificate was issued by an authority that isn't trusted by your system. This could be a private CA or an untrusted issuer."
            case let .trustFailure(status):
                "The system could not verify this certificate (error code: \(status)). This may indicate a configuration issue or security problem."
            }
        }
    }
}

// MARK: - Certificate Evaluator

/// Extracts certificate details from a SecTrust object.
///
/// This evaluator is designed to work alongside WebKit's built-in trust evaluation.
/// WebKit handles the actual SSL policy validation through its authentication challenge
/// mechanism; this evaluator extracts certificate information for UI display purposes.
///
/// ## Thread Safety
///
/// All methods are `nonisolated` and can be called from any thread. The Security
/// framework APIs used here are thread-safe. This allows certificate evaluation
/// to happen off the main thread to avoid blocking UI.
///
/// ## Design Philosophy
///
/// Per Apple's documentation, custom trust evaluation should be avoided when possible.
/// Instead, rely on the system's default trust evaluation. This evaluator:
///
/// 1. Does NOT override WebKit's trust policies for authentication challenges
/// 2. Extracts certificate details for informational display only
/// 3. Uses `SecTrustEvaluateWithError` only to determine current trust state
///
/// ## References
///
/// - [Overriding TLS Chain Validation Correctly](https://developer.apple.com/documentation/security/preventing_insecure_network_connections)
/// - [Tech Note TN2232: HTTPS Server Trust Evaluation](https://developer.apple.com/library/archive/technotes/tn2232/_index.html)
nonisolated enum CertificateEvaluator {
    /// Extracts certificate information from a SecTrust object.
    ///
    /// Evaluates the current trust state and extracts certificate details for display.
    /// Does NOT modify the trust object's policies - respects whatever policies
    /// WebKit has already configured.
    ///
    /// - Parameters:
    ///   - trust: The SecTrust object to evaluate.
    ///   - host: The hostname (for self-signed detection heuristics only).
    /// - Returns: Certificate information with trust state and details.
    static func evaluate(_ trust: SecTrust?, for host: String?) -> CertificateInfo {
        guard let trust else {
            return .insecure
        }

        // Evaluate trust using whatever policies are already set by WebKit
        // Do NOT call SecTrustSetPolicies - WebKit has already configured
        // the appropriate SSL policy during the authentication challenge.
        // See: https://developer.apple.com/documentation/security/certificate_key_and_trust_services/trust/evaluating_a_trust_and_parsing_the_result
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(trust, &error)

        guard let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leafCertificate = certificates.first
        else {
            return .insecure
        }

        let details = CertificateDetails(certificate: leafCertificate)
        let chain = buildCertificateChain(from: certificates)
        let trustError = isValid ? nil : mapError(error, certificates: certificates, host: host)

        return CertificateInfo(
            trustState: isValid ? .valid : .invalid(trustError ?? .trustFailure(errSecInternalError)),
            subjectName: details.commonName,
            organization: details.organization,
            issuer: details.issuer,
            validFrom: details.notBefore,
            validUntil: details.notAfter,
            fingerprint: details.sha256Fingerprint,
            certificateChain: chain,
        )
    }

    /// Builds the certificate chain entries for display.
    private static func buildCertificateChain(from certificates: [SecCertificate]) -> [CertificateInfo.CertificateChainEntry] {
        certificates.enumerated().map { index, cert in
            let details = CertificateDetails(certificate: cert)
            let summary = SecCertificateCopySubjectSummary(cert) as String? ?? "Unknown"

            // A certificate is a root if it's self-issued (subject == issuer)
            // This is detected by checking if it's the last cert in chain
            // and comparing subject/issuer names where possible
            let isRoot = index == certificates.count - 1 && isSelfIssued(cert)

            return CertificateInfo.CertificateChainEntry(
                summary: summary,
                commonName: details.commonName,
                organization: details.organization,
                fingerprint: details.sha256Fingerprint ?? "Unknown",
                isLeaf: index == 0,
                isRoot: isRoot,
            )
        }
    }

    /// Checks if a certificate is self-issued (subject equals issuer).
    private static func isSelfIssued(_ certificate: SecCertificate) -> Bool {
        // Get subject and issuer sequences
        guard let subjectData = SecCertificateCopyNormalizedSubjectSequence(certificate),
              let issuerData = SecCertificateCopyNormalizedIssuerSequence(certificate)
        else {
            return false
        }
        return (subjectData as Data) == (issuerData as Data)
    }

    /// Maps Security framework errors to our trust error types.
    ///
    /// Includes self-signed detection by checking if the certificate chain
    /// consists of a single self-issued certificate.
    private static func mapError(
        _ error: CFError?,
        certificates: [SecCertificate],
        host _: String?,
    ) -> CertificateInfo.TrustError {
        // Check for self-signed certificate first
        // A self-signed cert has only one certificate in the chain and is self-issued
        if certificates.count == 1,
           let leaf = certificates.first,
           isSelfIssued(leaf) {
            return .selfSigned
        }

        guard let error else {
            return .trustFailure(errSecInternalError)
        }

        let code = OSStatus(CFErrorGetCode(error))

        switch code {
        case errSecCertificateExpired:
            return .expired
        case errSecCertificateNotValidYet:
            return .notYetValid
        case errSecHostNameMismatch:
            return .hostnameMismatch
        case errSecCertificateRevoked:
            return .revoked
        case errSecCreateChainFailed, errSecNotTrusted:
            // Check if it might be self-signed even with chain building failure
            if certificates.count == 1,
               let leaf = certificates.first,
               isSelfIssued(leaf) {
                return .selfSigned
            }
            return .untrustedRoot
        default:
            return parseUnderlyingError(error) ?? .trustFailure(code)
        }
    }

    /// Attempts to extract more specific error info from underlying errors.
    private static func parseUnderlyingError(_ error: CFError) -> CertificateInfo.TrustError? {
        guard let userInfo = CFErrorCopyUserInfo(error) as? [String: Any],
              let underlying = userInfo["NSUnderlyingError"] as? NSError
        else {
            return nil
        }

        switch OSStatus(underlying.code) {
        case errSecCertificateExpired:
            return .expired
        case errSecCertificateNotValidYet:
            return .notYetValid
        default:
            return nil
        }
    }
}

// MARK: - Certificate Details Extraction

/// Extracts human-readable details from a SecCertificate.
private nonisolated struct CertificateDetails {
    let commonName: String?
    let organization: String?
    let issuer: String?
    let notBefore: Date?
    let notAfter: Date?
    let sha256Fingerprint: String?

    init(certificate: SecCertificate) {
        var cn: CFString?
        if SecCertificateCopyCommonName(certificate, &cn) == errSecSuccess {
            self.commonName = cn as String?
        } else {
            self.commonName = nil
        }

        let values = SecCertificateCopyValues(certificate, nil, nil) as? [String: Any]

        self.organization = Self.extractOrganization(from: values)
        self.issuer = Self.extractIssuer(from: values)
        (self.notBefore, self.notAfter) = Self.extractValidityPeriod(from: values)
        self.sha256Fingerprint = Self.computeFingerprint(certificate)
    }

    // MARK: - OID Constants

    // Standard X.509 OIDs for certificate fields
    // See: https://www.alvestrand.no/objectid/2.5.4.html
    private enum OID {
        static let organization = "2.5.4.10"
        static let issuer = "2.16.840.1.113741.2.1.1.1.8"
        static let validity = "2.5.29.24"
    }

    // MARK: - Extraction Helpers

    private static func extractOrganization(from values: [String: Any]?) -> String? {
        guard let dict = values?[OID.organization] as? [String: Any],
              let orgValues = dict["value"] as? [String]
        else {
            return nil
        }
        return orgValues.first
    }

    private static func extractIssuer(from values: [String: Any]?) -> String? {
        guard let dict = values?[OID.issuer] as? [String: Any],
              let value = dict["value"]
        else {
            return nil
        }
        return String(describing: value)
    }

    private static func extractValidityPeriod(from values: [String: Any]?) -> (Date?, Date?) {
        guard let dict = values?[OID.validity] as? [String: Any],
              let dates = dict["value"] as? [Date]
        else {
            return (nil, nil)
        }
        return (dates.first, dates.last)
    }

    private static func computeFingerprint(_ certificate: SecCertificate) -> String {
        let data = SecCertificateCopyData(certificate) as Data
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
