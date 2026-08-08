import SwiftUI
import UniformTypeIdentifiers

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(SiteSettingsManager.self) private var siteSettingsManager
    @Environment(BrowserState.self) private var browserState
    let highlightedItemId: String?

    @State private var cliHelperStatus: CLIHelperStatus?
    @State private var isInstallingCLIHelper = false
    @State private var showResetAlert = false
    @State private var showResetActivationAlert = false
    @State private var showJavaScriptSitesSheet = false
    @State private var whitelistedSitesCount: Int = 0
    @State private var allowedClients: [AllowedClient] = []
    @State private var showAddClientPicker = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Enable JavaScript", isOn: $settings.enableJavaScript)
                    .highlightable(id: "advanced.javascript", highlightedItemId: highlightedItemId)

                // Only show whitelist options when global JS is disabled
                if !settings.enableJavaScript {
                    Toggle("Allow site-specific whitelist", isOn: $settings.allowJavaScriptWhitelist)
                        .highlightable(id: "advanced.javascriptWhitelist", highlightedItemId: highlightedItemId)

                    if settings.allowJavaScriptWhitelist {
                        // Show whitelist management
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Whitelisted Sites")
                                Text(javaScriptSitesDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Manage…") {
                                showJavaScriptSitesSheet = true
                            }
                        }
                        .highlightable(id: "advanced.javascriptSites", highlightedItemId: highlightedItemId)
                    }
                }
            } header: {
                Text("JavaScript")
            } footer: {
                if !settings.enableJavaScript {
                    if settings.allowJavaScriptWhitelist {
                        Text("JavaScript is globally disabled. Whitelisted sites can still run JavaScript.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("JavaScript is disabled for all sites. Enable the whitelist to allow specific domains.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Allow pop-up windows", isOn: $settings.allowPopups)
                    .highlightable(id: "advanced.popups", highlightedItemId: highlightedItemId)
            } header: {
                Text("Windows")
            } footer: {
                Text("Allow websites to open new windows. Per-site overrides can be set in Privacy > Site Settings.")
            }

            controlServerSection

            Section {
                Toggle("Allow bypassing certificate errors", isOn: $settings.allowSSLCertificateBypass)
                    .highlightable(id: "advanced.sslBypass", highlightedItemId: highlightedItemId)
            } header: {
                Text("Security")
            } footer: {
                Text("When enabled, you can proceed to sites with invalid SSL certificates after viewing a warning. Only use for trusted development servers.")
            }

            Section {
                Toggle("Automatically recover crashed tabs", isOn: $settings.enableAutoCrashRecovery)
                    .highlightable(id: "advanced.crashRecovery", highlightedItemId: highlightedItemId)

                if settings.enableAutoCrashRecovery {
                    Picker("Crash threshold", selection: $settings.crashThreshold) {
                        Text("2 crashes").tag(2)
                        Text("3 crashes").tag(3)
                        Text("5 crashes").tag(5)
                        Text("10 crashes").tag(10)
                    }
                    .highlightable(id: "advanced.crashThreshold", highlightedItemId: highlightedItemId)

                    Picker("Time window", selection: $settings.crashTimeWindowSeconds) {
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                    }
                    .highlightable(id: "advanced.crashTimeWindow", highlightedItemId: highlightedItemId)
                }
            } header: {
                Text("Crash Recovery")
            } footer: {
                Text("Automatically reload tabs when web content crashes. Recovery stops if a page crashes repeatedly within the time window.")
            }

            Section("Data") {
                Button("Reset All Settings…") {
                    showResetAlert = true
                }
                .foregroundStyle(.red)
                .highlightable(id: "advanced.reset", highlightedItemId: highlightedItemId)
            }

            #if DEBUG
            Section {
                Button("Reset Activation & Onboarding") {
                    showResetActivationAlert = true
                }
                .foregroundStyle(.red)
            } header: {
                Text("Debug")
            } footer: {
                Text("Clears activation state and onboarding flag. The onboarding flow will appear on next launch.")
            }
            #endif
        }
        .formStyle(.grouped)
        .onAppear {
            refreshWhitelistCount()
            loadAllowedClients()
        }
        .onChange(of: settings.allowedControlClientsJSON) {
            loadAllowedClients()
        }
        .fileImporter(
            isPresented: $showAddClientPicker,
            allowedContentTypes: [.unixExecutable, .exe, .application],
            allowsMultipleSelection: false,
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                addClientFromURL(url)
            }
        }
        .alert("Reset Settings", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
            }
        } message: {
            Text("This will reset all settings to their default values. This action cannot be undone.")
        }
        #if DEBUG
        .alert("Reset Activation", isPresented: $showResetActivationAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                settings.isActivated = false
                settings.activationCode = nil
                settings.hasCompletedOnboarding = false
                settings.telemetryEnabled = false
                settings.lastHeartbeatDate = nil
            }
        } message: {
            Text("This will clear activation and onboarding state. Restart the app to see the onboarding flow.")
        }
        #endif
        .sheet(isPresented: $showJavaScriptSitesSheet, onDismiss: refreshWhitelistCount) {
            JavaScriptSitesSheet(globalJSEnabled: settings.enableJavaScript)
        }
    }

    // MARK: - Control Server Section

    @ViewBuilder
    private var controlServerSection: some View {
        @Bindable var settings = settings

        Section {
            Text("Refrax includes a command-line tool for controlling the browser from the terminal or AI agents. Run `refrax-ctl -h` for usage.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            cliHelperRow

            Picker("Access Mode", selection: $settings.controlAccessModeRaw) {
                ForEach(ControlAccessMode.allCases, id: \.rawValue) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .highlightable(id: "advanced.controlAccess", highlightedItemId: highlightedItemId)

            if settings.controlAccessMode == .prompt {
                if allowedClients.isEmpty {
                    Text("No allowed apps")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(allowedClients.enumerated()), id: \.offset) { index, client in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: client.path))
                                .resizable()
                                .frame(width: 20, height: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(client.displayName)
                                    .font(.body)
                                Text(client.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                removeAllowedClient(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button("Add App…") {
                    showAddClientPicker = true
                }
            }
        } header: {
            Text("Control Server")
        } footer: {
            Text(settings.controlAccessMode.description)
        }
    }

    /// Shows the CLI helper's install state with an install/update button.
    ///
    /// Installation is silent when `/usr/local/bin` is user-writable; otherwise
    /// the button triggers the system administrator prompt directly — clicking
    /// it is the consent, so no extra confirmation dialog is shown.
    @ViewBuilder
    private var cliHelperRow: some View {
        HStack {
            switch cliHelperStatus {
            case .upToDate:
                Label("Command-line tool installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            case .notInstalled:
                Label("Command-line tool not installed", systemImage: "terminal")
            case .outdated:
                Label("Command-line tool update available", systemImage: "terminal")
            case .missingFromBundle, nil:
                Label("Command-line tool unavailable in this build", systemImage: "terminal")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let cliHelperStatus, cliHelperStatus.needsInstall {
                Button(cliHelperStatus == .notInstalled ? "Install…" : "Update…") {
                    installCLIHelper()
                }
                .disabled(isInstallingCLIHelper)
            }
        }
        .task {
            cliHelperStatus = RefraxControlHost.cliHelperStatus()
        }
    }

    /// Installs the CLI helper, escalating to the administrator prompt when needed.
    private func installCLIHelper() {
        isInstallingCLIHelper = true
        Task {
            let installed = await RefraxControlHost.installCLIHelperWithAuthorization()
            cliHelperStatus = RefraxControlHost.cliHelperStatus()
            if installed {
                browserState.cliHelperNeedsPrivilegedInstall = false
            }
            isInstallingCLIHelper = false
        }
    }

    private func loadAllowedClients() {
        guard let data = settings.allowedControlClientsJSON.data(using: .utf8),
              let clients = try? JSONDecoder().decode([AllowedClient].self, from: data)
        else {
            allowedClients = []
            return
        }
        allowedClients = clients
    }

    private func removeAllowedClient(at index: Int) {
        guard allowedClients.indices.contains(index) else { return }
        allowedClients.remove(at: index)
        saveAllowedClients()
    }

    private func addClientFromURL(_ url: URL) {
        let path = url.path
        let displayName = url.lastPathComponent
        let client = AllowedClient(path: path, signingIdentifier: nil, displayName: displayName)
        guard !allowedClients.contains(client) else { return }
        allowedClients.append(client)
        saveAllowedClients()
    }

    private func saveAllowedClients() {
        if let data = try? JSONEncoder().encode(allowedClients),
           let json = String(data: data, encoding: .utf8) {
            settings.allowedControlClientsJSON = json
        }
    }

    // MARK: - JavaScript

    private var javaScriptSitesDescription: String {
        if whitelistedSitesCount > 0 {
            "\(whitelistedSitesCount) site\(whitelistedSitesCount == 1 ? "" : "s") whitelisted"
        } else {
            "No sites whitelisted"
        }
    }

    private func refreshWhitelistCount() {
        whitelistedSitesCount = siteSettingsManager.fetchSitesWithJavaScriptEnabled().count
    }
}

// MARK: - JavaScript Sites Sheet

private struct JavaScriptSitesSheet: View {
    let globalJSEnabled: Bool
    @Environment(SiteSettingsManager.self) private var siteSettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var showAddSiteSheet = false
    @State private var allSiteSettings: [SiteSettings] = []

    var body: some View {
        NavigationStack {
            List {
                if globalJSEnabled {
                    // Global JS enabled - show sites with JS disabled (blocklist)
                    Section {
                        ForEach(blockedSites) { site in
                            JavaScriptSiteRow(site: site, globalJSEnabled: globalJSEnabled)
                        }
                        .onDelete(perform: deleteBlockedSites)
                    } header: {
                        Text("JavaScript Disabled")
                    } footer: {
                        Text("JavaScript is enabled globally. Sites listed here have JavaScript disabled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Global JS disabled - show sites with JS enabled (whitelist)
                    Section {
                        ForEach(whitelistedSites) { site in
                            JavaScriptSiteRow(site: site, globalJSEnabled: globalJSEnabled)
                        }
                        .onDelete(perform: deleteWhitelistedSites)
                    } header: {
                        Text("JavaScript Enabled (Whitelist)")
                    } footer: {
                        Text("JavaScript is disabled globally. Sites listed here have JavaScript enabled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if relevantSites.isEmpty {
                    ContentUnavailableView {
                        Label(
                            globalJSEnabled ? "No Blocked Sites" : "No Whitelisted Sites",
                            systemImage: globalJSEnabled ? "checkmark.shield" : "shield.slash",
                        )
                    } description: {
                        Text(
                            globalJSEnabled
                                ? "All sites can run JavaScript."
                                : "No sites have been whitelisted to run JavaScript.",
                        )
                    } actions: {
                        Button("Add Site") {
                            showAddSiteSheet = true
                        }
                    }
                }
            }
            .navigationTitle(globalJSEnabled ? "JavaScript Blocklist" : "JavaScript Whitelist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSiteSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                refreshSiteSettings()
            }
        }
        .frame(minWidth: 450, minHeight: 350)
        .sheet(isPresented: $showAddSiteSheet) {
            AddJavaScriptSiteSheet(globalJSEnabled: globalJSEnabled) {
                refreshSiteSettings()
            }
        }
    }

    private var relevantSites: [SiteSettings] {
        globalJSEnabled ? blockedSites : whitelistedSites
    }

    private var blockedSites: [SiteSettings] {
        allSiteSettings.filter { !$0.allowJavaScript }
    }

    private var whitelistedSites: [SiteSettings] {
        allSiteSettings.filter(\.allowJavaScript)
    }

    private func refreshSiteSettings() {
        allSiteSettings = siteSettingsManager.fetchAllSiteSettings()
    }

    private func deleteBlockedSites(at offsets: IndexSet) {
        let currentBlockedSites = blockedSites
        let sitesToDelete = offsets.compactMap { index in
            index < currentBlockedSites.count ? currentBlockedSites[index] : nil
        }
        for site in sitesToDelete {
            siteSettingsManager.delete(for: site.domain)
        }
        refreshSiteSettings()
    }

    private func deleteWhitelistedSites(at offsets: IndexSet) {
        let currentWhitelistedSites = whitelistedSites
        let sitesToDelete = offsets.compactMap { index in
            index < currentWhitelistedSites.count ? currentWhitelistedSites[index] : nil
        }
        for site in sitesToDelete {
            siteSettingsManager.delete(for: site.domain)
        }
        refreshSiteSettings()
    }
}

// MARK: - JavaScript Site Row

private struct JavaScriptSiteRow: View {
    @Bindable var site: SiteSettings
    let globalJSEnabled: Bool
    @Environment(SiteSettingsManager.self) private var siteSettingsManager

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(site.domain)
                    .font(.body)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $site.allowJavaScript)
                .labelsHidden()
        }
        .onChange(of: site.allowJavaScript) {
            siteSettingsManager.save(site)
        }
    }

    private var statusText: String {
        if globalJSEnabled {
            site.allowJavaScript ? "JavaScript enabled" : "JavaScript disabled"
        } else {
            site.allowJavaScript ? "Whitelisted" : "Blocked (default)"
        }
    }
}

// MARK: - Add JavaScript Site Sheet

private struct AddJavaScriptSiteSheet: View {
    let globalJSEnabled: Bool
    let onAdd: () -> Void

    @Environment(SiteSettingsManager.self) private var siteSettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var domain = ""

    private var isValid: Bool {
        !domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var normalizedDomain: String {
        var d = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Remove protocol if present
        if d.hasPrefix("https://") { d = String(d.dropFirst(8)) }
        if d.hasPrefix("http://") { d = String(d.dropFirst(7)) }
        // Remove trailing slash
        if d.hasSuffix("/") { d = String(d.dropLast()) }
        // Remove www. prefix
        if d.hasPrefix("www.") { d = String(d.dropFirst(4)) }
        return d
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Domain (e.g., example.com)", text: $domain)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                } footer: {
                    if globalJSEnabled {
                        Text("JavaScript will be disabled for this domain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("JavaScript will be enabled for this domain (whitelisted).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(globalJSEnabled ? "Block JavaScript" : "Whitelist Site")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addSite()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 350, minHeight: 180)
    }

    private func addSite() {
        let site = siteSettingsManager.settingsOrCreate(for: normalizedDomain)
        // If global JS is enabled, we're adding to blocklist (disable JS)
        // If global JS is disabled, we're adding to whitelist (enable JS)
        site.allowJavaScript = !globalJSEnabled
        siteSettingsManager.save(site)
        onAdd()
        dismiss()
    }
}
