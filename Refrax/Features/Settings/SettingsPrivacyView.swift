import SwiftUI

// MARK: - Privacy Settings

struct PrivacySettingsView: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(HistoryManager.self) private var historyManager
    @Environment(AutoFillState.self) private var autoFillState
    @Environment(SiteSettingsManager.self) private var siteSettingsManager

    let highlightedItemId: String?

    @State private var showClearHistoryAlert = false
    @State private var showClearDomainSheet = false
    @State private var showCustomRedirectSheet = false
    @State private var showAppRedirectSheet = false
    @State private var showGPCHeaderSitesSheet = false
    @State private var showSiteSettingsDashboard = false
    @State private var showRoutingRulesSheet = false
    @State private var showCookieInspector = false
    @State private var gpcAllowedCount: Int = 0
    @State private var gpcBlockedCount: Int = 0
    @State private var siteSettingsCount: Int = 0

    var body: some View {
        @Bindable var settings = settings

        let privacySettings = settings.privacyProtection

        Form {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Site Settings")
                        Text("\(siteSettingsCount) site\(siteSettingsCount == 1 ? "" : "s") with custom settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Manage…") {
                        showSiteSettingsDashboard = true
                    }
                }
                .highlightable(id: "privacy.siteSettings", highlightedItemId: highlightedItemId)
            } header: {
                Text("Per-Site Settings")
            } footer: {
                Text("Manage zoom, JavaScript, permissions, and other settings for individual websites.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tracking") {
                Toggle("Block third-party cookies", isOn: $settings.blockThirdPartyCookies)
                    .highlightable(id: "privacy.thirdPartyCookies", highlightedItemId: highlightedItemId)

                Toggle("Send Do Not Track header", isOn: $settings.doNotTrack)
                    .highlightable(id: "privacy.doNotTrack", highlightedItemId: highlightedItemId)

                Toggle("Enable Global Privacy Control", isOn: $settings.enableGlobalPrivacyControl)
                    .help("Sends Sec-GPC and exposes navigator.globalPrivacyControl to participating sites")
                    .highlightable(id: "privacy.gpc", highlightedItemId: highlightedItemId)

                Toggle("GPC telemetry", isOn: $settings.enableGPCTelemetry)
                    .help("Logs when a site reads the GPC signal (local-only)")
                    .highlightable(id: "privacy.gpcTelemetry", highlightedItemId: highlightedItemId)

                Toggle("Auto-dismiss cookie banners", isOn: $settings.enableAutoConsent)
                    .help("Automatically clicks 'reject all' on cookie consent popups")
                    .highlightable(id: "privacy.autoConsent", highlightedItemId: highlightedItemId)

                Toggle("Hide sign-in prompts", isOn: $settings.hideSignInPrompts)
                    .help("Hides 'Sign in with Google' and browser recommendation banners")
                    .highlightable(id: "privacy.hideSignInPrompts", highlightedItemId: highlightedItemId)
            }

            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Allowed Domains")
                        Text("\(gpcAllowedCount) domain\(gpcAllowedCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Manage…") {
                        showGPCHeaderSitesSheet = true
                    }
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text("Per-Site Overrides")
                        Text(gpcOverridesDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Manage per-site in page settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("GPC Header Sites")
            } footer: {
                Text("The GPC header is sent only to domains explicitly allowed here; blocked entries force omission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Allow text selection and copying", isOn: $settings.contentProtectionBypassEnabled)
                    .highlightable(id: "privacy.contentProtection", highlightedItemId: highlightedItemId)

                Toggle("Block page leave alerts", isOn: $settings.disableBeforeUnloadAlerts)
                    .highlightable(id: "privacy.beforeUnloadAlerts", highlightedItemId: highlightedItemId)

                Toggle("Disable scroll hijacking", isOn: $settings.disableScrollHijacking)
                    .highlightable(id: "privacy.scrollHijacking", highlightedItemId: highlightedItemId)
            } header: {
                Text("Web Behavior")
            } footer: {
                Text("Override website restrictions on content interaction. Some sites may not function correctly with these options enabled.")
            }

            Section {
                Toggle("Force native video controls", isOn: $settings.forceNativeVideoControls)
                    .help("Shows browser controls on all videos for AirPlay, PiP, and standard playback")
                    .highlightable(id: "privacy.nativeVideoControls", highlightedItemId: highlightedItemId)

                if settings.forceNativeVideoControls {
                    HStack {
                        Text("Default playback speed:")
                            .foregroundStyle(.secondary)
                        Picker("", selection: $settings.defaultVideoSpeed) {
                            Text("0.5×").tag(0.5)
                            Text("0.75×").tag(0.75)
                            Text("1.0×").tag(1.0)
                            Text("1.25×").tag(1.25)
                            Text("1.5×").tag(1.5)
                            Text("2.0×").tag(2.0)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    .highlightable(id: "privacy.videoSpeed", highlightedItemId: highlightedItemId)
                }
            } header: {
                Text("Media")
            } footer: {
                Text("Control video playback behavior across all websites.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable link protection", isOn: Binding(
                    get: { privacySettings.enableLinkProtection },
                    set: { privacySettings.enableLinkProtection = $0 },
                ))
                .highlightable(id: "privacy.linkProtection", highlightedItemId: highlightedItemId)

                if privacySettings.enableLinkProtection {
                    Toggle("Remove tracking parameters", isOn: Binding(
                        get: { privacySettings.removeTrackingParameters },
                        set: { privacySettings.removeTrackingParameters = $0 },
                    ))
                    .help("Removes utm_source, fbclid, gclid, and other tracking parameters from URLs")
                    .highlightable(id: "privacy.trackingParameters", highlightedItemId: highlightedItemId)

                    Toggle("Convert AMP links", isOn: Binding(
                        get: { privacySettings.convertAMPLinks },
                        set: { privacySettings.convertAMPLinks = $0 },
                    ))
                    .help("Redirects Google AMP cache URLs to the original publisher")
                    .highlightable(id: "privacy.ampLinks", highlightedItemId: highlightedItemId)

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Expand URL shorteners", isOn: Binding(
                            get: { privacySettings.expandURLShorteners },
                            set: { privacySettings.expandURLShorteners = $0 },
                        ))
                        .help("Expands bit.ly, t.co, and other shortened URLs before navigation")

                        if privacySettings.expandURLShorteners {
                            HStack {
                                Text("Expansion timeout:")
                                    .foregroundStyle(.secondary)
                                Picker("", selection: Binding(
                                    get: { privacySettings.shortenerExpansionTimeout },
                                    set: { privacySettings.shortenerExpansionTimeout = $0 },
                                )) {
                                    Text("3 seconds").tag(3.0)
                                    Text("5 seconds").tag(5.0)
                                    Text("10 seconds").tag(10.0)
                                }
                                .labelsHidden()
                                .fixedSize()
                            }
                            .padding(.leading, 20)
                        }
                    }
                    .highlightable(id: "privacy.urlShorteners", highlightedItemId: highlightedItemId)
                }
            } header: {
                Text("Link Protection")
            } footer: {
                Text("Clean URLs during navigation to remove tracking and reveal link destinations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Custom Redirects")
                        Text("\(privacySettings.customRedirects.count) rules")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit…") {
                        showCustomRedirectSheet = true
                    }
                }
                .highlightable(id: "privacy.customRedirects", highlightedItemId: highlightedItemId)

                HStack {
                    VStack(alignment: .leading) {
                        Text("App Redirects")
                        Text("\(privacySettings.appRedirectRules.count) rules")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit…") {
                        showAppRedirectSheet = true
                    }
                }
                .highlightable(id: "privacy.appRedirects", highlightedItemId: highlightedItemId)
            } header: {
                Text("Redirects")
            } footer: {
                Text("Redirect URLs to alternative frontends (e.g., Twitter → Nitter) or open in external apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("URL Routing Rules")
                        Text("Automatically direct URLs to spaces, groups, or Glimpse windows")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Manage…") {
                        showRoutingRulesSheet = true
                    }
                }
                .highlightable(id: "privacy.routingRules", highlightedItemId: highlightedItemId)
            } header: {
                Text("Routing")
            } footer: {
                Text("Create rules to automatically route URLs based on domain, path, or time conditions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Space Locking

            Section {
                Picker("Auto-lock timeout:", selection: $settings.defaultLockTimeout) {
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                    Text("15 minutes").tag(900)
                    Text("30 minutes").tag(1_800)
                    Text("1 hour").tag(3_600)
                    Text("Never").tag(Int.max)
                }
                .highlightable(id: "privacy.lockTimeout", highlightedItemId: highlightedItemId)
            } header: {
                Text("Space Locking")
            } footer: {
                Text("Locked spaces automatically re-lock after this period of inactivity. Enable locking for individual spaces via right-click on the space icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Diagnostics

            Section {
                Toggle("Send anonymous usage data", isOn: $settings.telemetryEnabled)
                    .disabled(Constants.App.releaseChannel.forceTelemetry)
                    .highlightable(id: "privacy.telemetry", highlightedItemId: highlightedItemId)
            } header: {
                Text("Diagnostics")
            } footer: {
                if Constants.App.releaseChannel.forceTelemetry {
                    Text("Diagnostics are always enabled during the alpha. This will become optional in a future release.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Once daily on launch: anonymous device identifier, app version, macOS version, and language.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Passwords & AutoFill

            Section {
                Picker("AutoFill mode:", selection: $settings.autoFillMode) {
                    ForEach(AutoFillMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .highlightable(id: "privacy.autofill", highlightedItemId: highlightedItemId)

                if settings.autoFillMode == .builtIn {
                    Toggle("Require Touch ID to AutoFill", isOn: $settings.requireAuthForAutoFill)
                        .highlightable(id: "privacy.requireAuthAutoFill", highlightedItemId: highlightedItemId)
                }
            } header: {
                Text("Passwords & AutoFill")
            } footer: {
                autoFillFooterText
            }

            Section {
                Toggle("Automatically delete old history", isOn: $settings.automaticHistoryCleanup)
                    .highlightable(id: "privacy.autoDeleteHistory", highlightedItemId: highlightedItemId)

                if settings.automaticHistoryCleanup {
                    Picker("Delete history older than", selection: $settings.historyRetentionDays) {
                        Text("1 week").tag(7)
                        Text("1 month").tag(30)
                        Text("3 months").tag(90)
                        Text("6 months").tag(180)
                        Text("1 year").tag(365)
                    }
                    .highlightable(id: "privacy.retentionPeriod", highlightedItemId: highlightedItemId)
                }

                HStack {
                    Button("Clear All History") {
                        showClearHistoryAlert = true
                    }
                    .foregroundStyle(.red)
                    .highlightable(id: "privacy.clearHistory", highlightedItemId: highlightedItemId)

                    Button("Clear History for Site…") {
                        showClearDomainSheet = true
                    }
                    .highlightable(id: "privacy.clearDomainHistory", highlightedItemId: highlightedItemId)
                }
            } header: {
                Text("History")
            } footer: {
                Text("Browsing history is stored locally and used for autocomplete suggestions.")
            }

            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Cookie Inspector")
                        Text("View and manage cookies across all sites and spaces")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open…") {
                        showCookieInspector = true
                    }
                }
                .highlightable(id: "privacy.cookieInspector", highlightedItemId: highlightedItemId)
            } header: {
                Text("Cookies")
            } footer: {
                Text("Inspect, edit, and delete cookies stored by websites. Cookies are shown per data store (spaces with separate data).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshCounts)
        .alert("Clear History", isPresented: $showClearHistoryAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                historyManager.clearAllHistory()
            }
        } message: {
            Text("This will delete all browsing history. This action cannot be undone.")
        }
        .sheet(isPresented: $showCustomRedirectSheet) {
            CustomRedirectsSheet()
        }
        .sheet(isPresented: $showAppRedirectSheet) {
            AppRedirectsSheet()
        }
        .sheet(isPresented: $showGPCHeaderSitesSheet, onDismiss: refreshCounts) {
            GPCHeaderSitesSheet()
        }
        .sheet(isPresented: $showSiteSettingsDashboard, onDismiss: refreshCounts) {
            SiteSettingsDashboardView()
        }
        .sheet(isPresented: $showRoutingRulesSheet) {
            RoutingRulesSettingsView()
                .frame(minWidth: 550, minHeight: 450)
        }
        .sheet(isPresented: $showClearDomainSheet) {
            ClearDomainHistorySheet()
        }
        .sheet(isPresented: $showCookieInspector) {
            CookieInspectorView()
        }
    }

    private var gpcOverridesDescription: String {
        let total = gpcAllowedCount + gpcBlockedCount
        if total == 0 {
            return "No overrides"
        }
        let pluralSuffix = total == 1 ? "" : "s"
        return "\(total) site\(pluralSuffix) overridden"
    }

    @ViewBuilder
    private var autoFillFooterText: some View {
        let text = switch settings.autoFillMode {
        case .disabled:
            "AutoFill is disabled. Refrax won't show any credential popups, allowing password manager extensions to work without interference."
        case .systemOnly:
            "Only system pickers are shown (Passwords, Credit Cards, Contacts). No credential saving or generation. Good for using iCloud Keychain with an extension for other features."
        case .builtIn:
            "Full Safari-style autofill with credential saving, password generation, and system picker integration using the macOS Keychain."
        }

        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func refreshCounts() {
        let overrides = siteSettingsManager.fetchSitesWithGPCHeaderOverrides()
        gpcAllowedCount = overrides.count(where: { $0.gpcHeaderOverride == .allow })
        gpcBlockedCount = overrides.count(where: { $0.gpcHeaderOverride == .block })
        siteSettingsCount = siteSettingsManager.siteCount
    }
}
