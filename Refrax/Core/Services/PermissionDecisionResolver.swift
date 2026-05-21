import Foundation
import WebKit

/// Centralizes permission decision logic for WebKit permission requests.
///
/// This resolver looks up site-specific permission settings and maps them to
/// WebKit permission decisions. It handles:
/// - Camera and microphone access
/// - Device orientation and motion sensors
/// - Screen sharing (display capture)
/// - Geolocation
///
/// All methods return `.prompt` for domains without explicit settings.
struct PermissionDecisionResolver: Sendable {
    private let siteSettingsManager: SiteSettingsManager

    init(siteSettingsManager: SiteSettingsManager) {
        self.siteSettingsManager = siteSettingsManager
    }

    // MARK: - Camera & Microphone

    /// Resolves the camera permission for a domain.
    func cameraPermission(for domain: String) -> WKPermissionDecision {
        siteSettingsManager.settings(for: domain)?.cameraPermission.webKitDecision ?? .prompt
    }

    /// Resolves the microphone permission for a domain.
    func microphonePermission(for domain: String) -> WKPermissionDecision {
        siteSettingsManager.settings(for: domain)?.microphonePermission.webKitDecision ?? .prompt
    }

    /// Resolves combined camera and microphone permission.
    ///
    /// Returns `.deny` if either is denied, `.grant` if both are granted,
    /// and `.prompt` for all other cases.
    func cameraAndMicrophonePermission(for domain: String) -> WKPermissionDecision {
        guard let settings = siteSettingsManager.settings(for: domain) else {
            return .prompt
        }

        let cameraDecision = settings.cameraPermission.webKitDecision
        let micDecision = settings.microphonePermission.webKitDecision

        if cameraDecision == .deny || micDecision == .deny {
            return .deny
        }
        if cameraDecision == .grant, micDecision == .grant {
            return .grant
        }
        return .prompt
    }

    // MARK: - Device Sensors

    /// Resolves device sensor (orientation/motion) permission for a domain.
    func deviceSensorPermission(for domain: String) -> WKPermissionDecision {
        siteSettingsManager.settings(for: domain)?.deviceSensorPermission.webKitDecision ?? .prompt
    }

    // MARK: - Screen Sharing

    /// Resolves screen sharing permission for a domain.
    ///
    /// Returns `.screenPrompt` for allow/ask (shows system picker),
    /// and `.deny` for explicit deny.
    func screenSharingPermission(for domain: String) -> WKDisplayCapturePermissionDecision {
        let permission = siteSettingsManager.settings(for: domain)?.screenSharingPermission ?? .ask
        return switch permission {
        case .allow, .ask:
            // Both allow and ask show the system picker - the picker IS the consent UI
            .screenPrompt
        case .deny:
            .deny
        }
    }

    // MARK: - Geolocation

    /// Resolves geolocation permission for a domain.
    func locationPermission(for domain: String) -> WKPermissionDecision {
        siteSettingsManager.settings(for: domain)?.locationPermission.webKitDecision ?? .prompt
    }

    // MARK: - Device Sensor Authorization Handler

    /// Creates a decision handler closure for device sensor authorization.
    ///
    /// The returned closure can be passed to `WebPage.DeviceSensorAuthorization.init(decisionHandler:)`.
    ///
    /// - Parameter siteSettingsManager: Manager to look up site-specific permission settings.
    /// - Returns: A closure that resolves permissions based on the site's settings.
    static func makeDeviceSensorDecisionHandler(
        siteSettingsManager: SiteSettingsManager,
    ) -> @Sendable (
        WebPage.DeviceSensorAuthorization.Permission,
        WebPage.FrameInfo,
        WKSecurityOrigin,
    ) async -> WKPermissionDecision {
        let resolver = PermissionDecisionResolver(siteSettingsManager: siteSettingsManager)

        return { permission, _, securityOrigin in
            await MainActor.run {
                let domain = securityOrigin.host

                switch permission {
                case .deviceOrientationAndMotion:
                    return resolver.deviceSensorPermission(for: domain)

                case let .mediaCapture(captureType):
                    switch captureType {
                    case .camera:
                        return resolver.cameraPermission(for: domain)
                    case .microphone:
                        return resolver.microphonePermission(for: domain)
                    case .cameraAndMicrophone:
                        return resolver.cameraAndMicrophonePermission(for: domain)
                    @unknown default:
                        return .prompt
                    }

                @unknown default:
                    return .prompt
                }
            }
        }
    }
}
