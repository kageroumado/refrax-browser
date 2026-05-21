import SwiftUI

/// Popover for managing per-site settings.
///
/// Displays and allows modification of settings for a specific domain:
/// - Content settings (Reader mode, content blockers, zoom)
/// - Media settings (auto-play policy)
/// - Window settings (pop-up policy)
/// - Permissions (camera, microphone, screen sharing, location)
///
/// Settings are loaded from ``SiteSettingsManager`` on appear and saved
/// automatically when changed.
struct WebpageSettingsPopover: View {
    let domain: String

    @Environment(SiteSettingsManager.self) private var siteSettingsManager
    @Environment(ExtensionManager.self) private var extensionManager

    // MARK: - State

    @State private var useReaderWhenAvailable = false
    @State private var enableContentBlockers = true
    @State private var allowJavaScript = true
    @State private var disableAutoConsent = false
    @State private var neverSavePasswords = false
    @State private var pageZoom: Int = 100
    @State private var autoPlayPolicy: AutoPlayPolicy = .stopMediaWithSound
    @State private var popUpPolicy: PopUpPolicy = .blockAndNotify
    @State private var gpcHeaderOverride: GPCHeaderOverride = .useAllowlist
    @State private var cameraAccess: PermissionPolicy = .ask
    @State private var microphoneAccess: PermissionPolicy = .ask
    @State private var screenSharingAccess: PermissionPolicy = .ask
    @State private var locationAccess: PermissionPolicy = .ask
    @State private var deviceSensorAccess: PermissionPolicy = .ask
    @State private var websiteColoringPolicy: WebsiteColoringPolicy = .useDefault

    /// Whether we've loaded settings (prevents saving during initial load)
    @State private var isLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("When visiting \(domain):")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)

            // Reader & Content Blockers
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use Reader when available", isOn: $useReaderWhenAvailable)
                Toggle("Enable content blockers", isOn: $enableContentBlockers)
                Toggle("Allow JavaScript", isOn: $allowJavaScript)
                Toggle("Disable auto-dismiss cookie banners", isOn: $disableAutoConsent)
                Toggle("Never save passwords", isOn: $neverSavePasswords)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 13))

            Divider()
                .padding(.vertical, 12)

            // Page Settings
            VStack(spacing: 8) {
                SettingsRow(label: "Page Zoom:") {
                    Picker("", selection: $pageZoom) {
                        ForEach(Constants.AddressBar.zoomLevels, id: \.self) { value in
                            Text("\(value)%").tag(value)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                SettingsRow(label: "Auto-Play:") {
                    Picker("", selection: $autoPlayPolicy) {
                        ForEach(AutoPlayPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                SettingsRow(label: "Pop-up Windows:") {
                    Picker("", selection: $popUpPolicy) {
                        ForEach(PopUpPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                SettingsRow(label: "GPC Header:") {
                    Picker("", selection: $gpcHeaderOverride) {
                        ForEach(GPCHeaderOverride.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                SettingsRow(label: "Window Coloring:") {
                    Picker("", selection: $websiteColoringPolicy) {
                        ForEach(WebsiteColoringPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            Divider()
                .padding(.vertical, 12)

            // Permissions
            VStack(spacing: 8) {
                SettingsRow(label: "Camera:") {
                    Picker("", selection: $cameraAccess) {
                        ForEach(PermissionPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                SettingsRow(label: "Microphone:") {
                    Picker("", selection: $microphoneAccess) {
                        ForEach(PermissionPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                SettingsRow(label: "Screen Sharing:") {
                    Picker("", selection: $screenSharingAccess) {
                        ForEach(PermissionPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                SettingsRow(label: "Location:") {
                    Picker("", selection: $locationAccess) {
                        ForEach(PermissionPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                SettingsRow(label: "Motion Sensors:") {
                    Picker("", selection: $deviceSensorAccess) {
                        ForEach(PermissionPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            // Extensions section - only show if there are enabled extensions
            if !extensionManager.enabledExtensions.isEmpty {
                Divider()
                    .padding(.vertical, 12)

                extensionsSection
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear(perform: loadSettings)
        .onChange(of: useReaderWhenAvailable) { saveSettings() }
        .onChange(of: enableContentBlockers) { saveSettings() }
        .onChange(of: allowJavaScript) { saveSettings() }
        .onChange(of: disableAutoConsent) { saveSettings() }
        .onChange(of: neverSavePasswords) { saveSettings() }
        .onChange(of: pageZoom) { saveSettings() }
        .onChange(of: autoPlayPolicy) { saveSettings() }
        .onChange(of: popUpPolicy) { saveSettings() }
        .onChange(of: gpcHeaderOverride) { saveSettings() }
        .onChange(of: cameraAccess) { saveSettings() }
        .onChange(of: microphoneAccess) { saveSettings() }
        .onChange(of: screenSharingAccess) { saveSettings() }
        .onChange(of: locationAccess) { saveSettings() }
        .onChange(of: deviceSensorAccess) { saveSettings() }
        .onChange(of: websiteColoringPolicy) { saveSettings() }
    }

    // MARK: - Extensions Section

    @ViewBuilder
    private var extensionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Extensions")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(extensionManager.enabledExtensions) { ext in
                extensionRow(for: ext)
            }
        }
    }

    @ViewBuilder
    private func extensionRow(for ext: InstalledExtension) -> some View {
        HStack(spacing: 8) {
            extensionIcon(for: ext)
                .frame(width: 16, height: 16)

            Text(ext.displayName)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            Toggle("", isOn: extensionEnabledBinding(for: ext))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }

    @ViewBuilder
    private func extensionIcon(for ext: InstalledExtension) -> some View {
        if let iconData = ext.iconData, let nsImage = NSImage(data: iconData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.appAccentColor.opacity(0.15))
                .overlay {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func extensionEnabledBinding(for ext: InstalledExtension) -> Binding<Bool> {
        Binding(
            get: { !extensionManager.isExtensionDisabled(ext, forDomain: domain) },
            set: { newValue in
                extensionManager.setExtensionEnabled(ext, onDomain: domain, enabled: newValue)
            },
        )
    }

    // MARK: - Settings Management

    private func loadSettings() {
        guard !isLoaded else { return }

        if let settings = siteSettingsManager.settings(for: domain) {
            useReaderWhenAvailable = settings.useReaderWhenAvailable
            enableContentBlockers = settings.enableContentBlockers
            allowJavaScript = settings.allowJavaScript
            disableAutoConsent = settings.disableAutoConsent
            neverSavePasswords = settings.neverSavePasswords
            pageZoom = settings.pageZoom
            autoPlayPolicy = settings.autoPlayPolicy
            popUpPolicy = settings.popUpPolicy
            gpcHeaderOverride = settings.gpcHeaderOverride
            cameraAccess = settings.cameraPermission
            microphoneAccess = settings.microphonePermission
            screenSharingAccess = settings.screenSharingPermission
            locationAccess = settings.locationPermission
            deviceSensorAccess = settings.deviceSensorPermission
            websiteColoringPolicy = settings.websiteColoringPolicy
        }

        isLoaded = true
    }

    private func saveSettings() {
        guard isLoaded else { return }

        let settings = siteSettingsManager.settingsOrCreate(for: domain)
        settings.useReaderWhenAvailable = useReaderWhenAvailable
        settings.enableContentBlockers = enableContentBlockers
        settings.allowJavaScript = allowJavaScript
        settings.disableAutoConsent = disableAutoConsent
        settings.neverSavePasswords = neverSavePasswords
        settings.pageZoom = pageZoom
        settings.autoPlayPolicy = autoPlayPolicy
        settings.popUpPolicy = popUpPolicy
        settings.gpcHeaderOverride = gpcHeaderOverride
        settings.cameraPermission = cameraAccess
        settings.microphonePermission = microphoneAccess
        settings.screenSharingPermission = screenSharingAccess
        settings.locationPermission = locationAccess
        settings.deviceSensorPermission = deviceSensorAccess
        settings.websiteColoringPolicy = websiteColoringPolicy

        siteSettingsManager.save(settings)
    }
}

private struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
