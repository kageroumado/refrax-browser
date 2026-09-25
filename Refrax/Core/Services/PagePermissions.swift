import Foundation

/// Answers a page's permission requests: from the site's setting when it has one, from the
/// user through the page's prompts when the setting is Ask.
///
/// One path for every engine, so a site gets the same answer whichever engine renders it.
struct PagePermissions {
    let siteSettingsManager: SiteSettingsManager

    /// Whether `host` may use `kind`.
    func decide(_ kind: PermissionKind, host: String, prompts: PagePrompts) async -> Bool {
        switch policy(for: kind, host: host) {
        case .allow:
            return true
        case .deny:
            return false
        case .ask:
            switch await prompts.ask(.permission(kind: kind, origin: host)) {
            case .accept, .text:
                return true
            case .acceptAndRemember:
                remember(kind, allowed: true, host: host)
                return true
            case .declineAndRemember:
                remember(kind, allowed: false, host: host)
                return false
            case .decline:
                return false
            }
        }
    }

    /// The site's stored policy for `kind`.
    func policy(for kind: PermissionKind, host: String) -> PermissionPolicy {
        let settings = siteSettingsManager.settings(for: host)
        switch kind {
        case .camera:
            return settings?.cameraPermission ?? .ask
        case .microphone:
            return settings?.microphonePermission ?? .ask
        case .cameraAndMicrophone:
            let policies = [settings?.cameraPermission ?? .ask, settings?.microphonePermission ?? .ask]
            if policies.contains(.deny) { return .deny }
            return policies.allSatisfy { $0 == .allow } ? .allow : .ask
        case .geolocation:
            return settings?.locationPermission ?? .ask
        case .screenCapture:
            // The system's screen picker is the consent; the setting can only forbid it.
            return settings?.screenSharingPermission == .deny ? .deny : .allow
        case .notifications:
            // Notifications are per origin and decided by WebNotificationManager.
            return .deny
        case .clipboardRead:
            return .ask
        }
    }

    /// Stores the user's choice as the site's setting, where the kind has one.
    func remember(_ kind: PermissionKind, allowed: Bool, host: String) {
        guard kind.isRememberable else { return }
        let settings = siteSettingsManager.settingsOrCreate(for: host)
        let policy: PermissionPolicy = allowed ? .allow : .deny
        switch kind {
        case .camera:
            settings.cameraPermission = policy
        case .microphone:
            settings.microphonePermission = policy
        case .cameraAndMicrophone:
            settings.cameraPermission = policy
            settings.microphonePermission = policy
        case .geolocation:
            settings.locationPermission = policy
        case .screenCapture, .notifications, .clipboardRead:
            return
        }
        siteSettingsManager.save(settings)
        Logger.info("Saved \(kind.rawValue) permission for \(host): \(policy)", category: Logger.security)
    }
}

extension PermissionKind {
    /// Whether a choice can be saved as a site setting ("Always Allow").
    var isRememberable: Bool {
        switch self {
        case .camera, .microphone, .cameraAndMicrophone, .geolocation: true
        case .screenCapture, .notifications, .clipboardRead: false
        }
    }

    /// The thing asked for, as a sentence ends: "… would like to use your camera".
    var requestedResource: String {
        switch self {
        case .camera: "camera"
        case .microphone: "microphone"
        case .cameraAndMicrophone: "camera and microphone"
        case .geolocation: "location"
        case .screenCapture: "screen"
        case .notifications: "notifications"
        case .clipboardRead: "clipboard"
        }
    }

    var symbolName: String {
        switch self {
        case .camera: "video.fill"
        case .microphone: "mic.fill"
        case .cameraAndMicrophone: "video.badge.waveform.fill"
        case .geolocation: "location.fill"
        case .screenCapture: "rectangle.on.rectangle"
        case .notifications: "bell.fill"
        case .clipboardRead: "doc.on.clipboard"
        }
    }
}
