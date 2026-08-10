import SwiftUI

/// Dashboard for managing all per-site settings.
///
/// Presents a searchable list of all domains with custom settings,
/// showing a summary of configured options for each site. Supports
/// bulk operations (reset, delete) and individual site editing.
struct SiteSettingsDashboardView: View {
    @Environment(SiteSettingsManager.self) private var siteSettingsManager
    @Environment(BrowserSettings.self) private var browserSettings
    @Environment(\.dismiss) private var dismiss

    @State private var allSiteSettings: [SiteSettings] = []
    @State private var searchText = ""
    @State private var selectedDomains: Set<String> = []
    @State private var showDeleteConfirmation = false
    @State private var showClearAllConfirmation = false
    @State private var showAddDomainSheet = false
    @State private var editingSite: SiteSettings?

    private var filteredSettings: [SiteSettings] {
        if searchText.isEmpty {
            return allSiteSettings
        }
        return allSiteSettings.filter { $0.domain.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compact header with title, search, add, and done button
            HStack(spacing: 12) {
                Text("Site Settings")
                    .font(.headline)

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter domains", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 180)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))

                Button {
                    showAddDomainSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            globalDefaultsHeader
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

            siteList
        }
        .safeAreaInset(edge: .bottom) {
            if !selectedDomains.isEmpty {
                bulkActionsBar
            }
        }
        .frame(minWidth: 600, minHeight: 450)
        .onAppear(perform: refreshSites)
        .alert("Delete Selected Sites", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSites(Array(selectedDomains))
            }
        } message: {
            Text("Delete settings for \(selectedDomains.count) site\(selectedDomains.count == 1 ? "" : "s")? This cannot be undone.")
        }
        .alert("Clear All Site Settings", isPresented: $showClearAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                clearAllSites()
            }
        } message: {
            Text("Delete all custom site settings? This cannot be undone.")
        }
        .sheet(item: $editingSite) { site in
            SiteSettingsEditSheet(site: site, onSave: refreshSites)
        }
        .sheet(isPresented: $showAddDomainSheet) {
            AddDomainSheet(existingDomains: Set(allSiteSettings.map(\.domain))) { newSite in
                refreshSites()
                editingSite = newSite
            }
        }
    }

    // MARK: - Global Defaults Header

    private var globalDefaultsHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Global Defaults")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    DefaultChip(label: "JavaScript", value: browserSettings.enableJavaScript ? "Enabled" : "Disabled")
                    DefaultChip(label: "Popups", value: "Block")
                    DefaultChip(label: "Zoom", value: "100%")
                }
                GridRow {
                    DefaultChip(label: "Blockers", value: "On")
                    DefaultChip(label: "AutoConsent", value: browserSettings.enableAutoConsent ? "On" : "Off")
                    DefaultChip(label: "GPC", value: browserSettings.enableGlobalPrivacyControl ? "On" : "Off")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Site List

    private var siteList: some View {
        List(selection: $selectedDomains) {
            if filteredSettings.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView {
                        Label("No Custom Settings", systemImage: "globe")
                    } description: {
                        Text("Sites with custom zoom, permissions, or other settings will appear here.")
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        Text("No sites match \"\(searchText)\"")
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    ForEach(filteredSettings, id: \.domain) { site in
                        SiteSettingsRow(site: site) {
                            editingSite = site
                        }
                        .tag(site.domain)
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                    }
                    .onDelete(perform: deleteAtOffsets)
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Sites with Custom Settings")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("(\(allSiteSettings.count))")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        if !allSiteSettings.isEmpty {
                            Button("Clear All…") {
                                showClearAllConfirmation = true
                            }
                            .font(.subheadline)
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Bulk Actions Bar

    private var bulkActionsBar: some View {
        HStack(spacing: 16) {
            Text("\(selectedDomains.count) selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Reset Selected") {
                resetSelected()
            }
            .buttonStyle(.bordered)

            Button("Delete Selected", role: .destructive) {
                showDeleteConfirmation = true
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // MARK: - Actions

    private func refreshSites() {
        allSiteSettings = siteSettingsManager.fetchAllSiteSettings()
        selectedDomains = selectedDomains.filter { domain in
            allSiteSettings.contains { $0.domain == domain }
        }
    }

    private func deleteAtOffsets(_ offsets: IndexSet) {
        let domainsToDelete = offsets.map { filteredSettings[$0].domain }
        deleteSites(domainsToDelete)
    }

    private func deleteSites(_ domains: [String]) {
        siteSettingsManager.delete(for: domains)
        selectedDomains.subtract(domains)
        refreshSites()
    }

    private func resetSelected() {
        siteSettingsManager.resetToDefaults(for: Array(selectedDomains))
        selectedDomains.removeAll()
        refreshSites()
    }

    private func clearAllSites() {
        let allDomains = allSiteSettings.map(\.domain)
        siteSettingsManager.delete(for: allDomains)
        selectedDomains.removeAll()
        refreshSites()
    }
}

// MARK: - Default Chip

private struct DefaultChip: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.tertiary)
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

// MARK: - Site Settings Row

private struct SiteSettingsRow: View {
    let site: SiteSettings
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(site.domain)
                    .font(.body)
                    .fontWeight(.medium)

                settingsChips
            }

            Spacer(minLength: 16)

            Button {
                onEdit()
            } label: {
                Text("Edit")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var settingsChips: some View {
        let chips = buildChips()
        if chips.isEmpty {
            Text("No custom settings")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    SettingChip(text: chip)
                }
            }
        }
    }

    private func buildChips() -> [String] {
        var chips: [String] = []

        if site.pageZoom != 100 {
            chips.append("Zoom \(site.pageZoom)%")
        }

        if !site.allowJavaScript {
            chips.append("JavaScript Off")
        }

        if !site.enableContentBlockers {
            chips.append("Blockers Off")
        }

        if site.disableAutoConsent {
            chips.append("AutoConsent Off")
        }

        if site.gpcHeaderOverride != .useAllowlist {
            chips.append("GPC \(site.gpcHeaderOverride == .allow ? "Always" : "Never")")
        }

        if site.popUpPolicy != .blockAndNotify {
            chips.append("Popups \(site.popUpPolicy == .allow ? "Allow" : "Block")")
        }

        if site.autoPlayPolicy != .stopMediaWithSound {
            chips.append("Autoplay \(site.autoPlayPolicy == .allowAll ? "All" : "None")")
        }

        if site.useReaderWhenAvailable {
            chips.append("Reader")
        }

        if site.cameraPermission != .ask {
            chips.append("Camera \(site.cameraPermission == .allow ? "Allow" : "Deny")")
        }
        if site.microphonePermission != .ask {
            chips.append("Mic \(site.microphonePermission == .allow ? "Allow" : "Deny")")
        }
        if site.locationPermission != .ask {
            chips.append("Location \(site.locationPermission == .allow ? "Allow" : "Deny")")
        }

        // Appearance overrides
        if site.darkModeOverride != .auto {
            chips.append("Dark \(site.darkModeOverride == .always ? "On" : "Off")")
        }
        if site.pageFilterOverride != .auto {
            chips.append("Filter: \(site.pageFilterOverride.displayName)")
        }
        if site.backgroundRemovalOverride != .auto {
            chips.append("BG: \(site.backgroundRemovalOverride.displayName)")
        }
        if let bypass = site.contentProtectionBypass {
            chips.append("Copy \(bypass ? "Allow" : "Block")")
        }
        if site.websiteColoringPolicy != .useDefault {
            chips.append("Color \(site.websiteColoringPolicy == .allow ? "Allow" : "Block")")
        }
        if site.pipPreference != .system {
            chips.append("PiP \(site.pipPreference == .always ? "Always" : "Never")")
        }

        // Web behavior overrides
        if site.beforeUnloadAlertOverride != .useDefault {
            chips.append("Leave Alert \(site.beforeUnloadAlertOverride == .allow ? "Allow" : "Block")")
        }
        if site.scrollHijackingOverride != .useDefault {
            chips.append("Scroll \(site.scrollHijackingOverride == .allow ? "Allow" : "Native")")
        }
        if site.videoControlsOverride != .useDefault {
            chips.append("Video \(site.videoControlsOverride == .forceNative ? "Native" : "Site")")
        }
        if let speed = site.videoSpeedOverride {
            chips.append("Speed \(String(format: "%.2g", speed))×")
        }

        return chips
    }
}

// MARK: - Setting Chip

private struct SettingChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Site Settings Edit Sheet

struct SiteSettingsEditSheet: View {
    @Environment(SiteSettingsManager.self) private var siteSettingsManager
    @Environment(BrowserState.self) private var browserState
    @Environment(\.dismiss) private var dismiss

    let site: SiteSettings
    let onSave: () -> Void

    @State private var pageZoom: Double
    @State private var allowJavaScript: Bool
    @State private var enableContentBlockers: Bool
    @State private var disableAutoConsent: Bool
    @State private var popUpPolicy: PopUpPolicy
    @State private var autoPlayPolicy: AutoPlayPolicy
    @State private var gpcHeaderOverride: GPCHeaderOverride
    @State private var useReaderWhenAvailable: Bool
    @State private var cameraPermission: PermissionPolicy
    @State private var microphonePermission: PermissionPolicy
    @State private var screenSharingPermission: PermissionPolicy
    @State private var locationPermission: PermissionPolicy
    @State private var deviceSensorPermission: PermissionPolicy

    // Appearance overrides
    @State private var darkModeOverride: DarkModeOverride
    @State private var pageFilterOverride: PageFilterOverride
    @State private var backgroundRemovalOverride: BackgroundRemovalOverride
    @State private var contentProtectionBypass: Bool?
    @State private var websiteColoringPolicy: WebsiteColoringPolicy
    @State private var pipPreference: PiPPreference

    // Web behavior overrides
    @State private var beforeUnloadAlertOverride: BeforeUnloadAlertOverride
    @State private var scrollHijackingOverride: ScrollHijackingOverride
    @State private var videoControlsOverride: VideoControlsOverride
    @State private var videoSpeedOverride: Double?
    @State private var calmPage: Bool

    // Time limits
    @State private var timeLimitEnabled: Bool
    @State private var timeLimitMinutes: Int

    @State private var showResetConfirmation = false

    init(site: SiteSettings, onSave: @escaping () -> Void) {
        self.site = site
        self.onSave = onSave
        _pageZoom = State(initialValue: Double(site.pageZoom))
        _allowJavaScript = State(initialValue: site.allowJavaScript)
        _enableContentBlockers = State(initialValue: site.enableContentBlockers)
        _disableAutoConsent = State(initialValue: site.disableAutoConsent)
        _popUpPolicy = State(initialValue: site.popUpPolicy)
        _autoPlayPolicy = State(initialValue: site.autoPlayPolicy)
        _gpcHeaderOverride = State(initialValue: site.gpcHeaderOverride)
        _useReaderWhenAvailable = State(initialValue: site.useReaderWhenAvailable)
        _cameraPermission = State(initialValue: site.cameraPermission)
        _microphonePermission = State(initialValue: site.microphonePermission)
        _screenSharingPermission = State(initialValue: site.screenSharingPermission)
        _locationPermission = State(initialValue: site.locationPermission)
        _deviceSensorPermission = State(initialValue: site.deviceSensorPermission)
        // Appearance
        _darkModeOverride = State(initialValue: site.darkModeOverride)
        _pageFilterOverride = State(initialValue: site.pageFilterOverride)
        _backgroundRemovalOverride = State(initialValue: site.backgroundRemovalOverride)
        _contentProtectionBypass = State(initialValue: site.contentProtectionBypass)
        _websiteColoringPolicy = State(initialValue: site.websiteColoringPolicy)
        _pipPreference = State(initialValue: site.pipPreference)
        // Web behavior
        _beforeUnloadAlertOverride = State(initialValue: site.beforeUnloadAlertOverride)
        _scrollHijackingOverride = State(initialValue: site.scrollHijackingOverride)
        _videoControlsOverride = State(initialValue: site.videoControlsOverride)
        _videoSpeedOverride = State(initialValue: site.videoSpeedOverride)
        _calmPage = State(initialValue: site.calmPage)
        // Time limits initialized in task
        _timeLimitEnabled = State(initialValue: false)
        _timeLimitMinutes = State(initialValue: 30)
    }

    var body: some View {
        NavigationStack {
            Form {
                SiteSettingsContentSection(
                    pageZoom: $pageZoom,
                    allowJavaScript: $allowJavaScript,
                    enableContentBlockers: $enableContentBlockers,
                    useReaderWhenAvailable: $useReaderWhenAvailable,
                    popUpPolicy: $popUpPolicy,
                    autoPlayPolicy: $autoPlayPolicy,
                )

                SiteSettingsAppearanceSection(
                    darkModeOverride: $darkModeOverride,
                    pageFilterOverride: $pageFilterOverride,
                    backgroundRemovalOverride: $backgroundRemovalOverride,
                    contentProtectionBypass: $contentProtectionBypass,
                    websiteColoringPolicy: $websiteColoringPolicy,
                    pipPreference: $pipPreference,
                )

                SiteSettingsPrivacySection(
                    disableAutoConsent: $disableAutoConsent,
                    gpcHeaderOverride: $gpcHeaderOverride,
                )

                SiteSettingsBehaviorSection(
                    beforeUnloadAlertOverride: $beforeUnloadAlertOverride,
                    scrollHijackingOverride: $scrollHijackingOverride,
                    videoControlsOverride: $videoControlsOverride,
                    videoSpeedOverride: $videoSpeedOverride,
                    calmPage: $calmPage,
                )

                SiteSettingsPermissionsSection(
                    cameraPermission: $cameraPermission,
                    microphonePermission: $microphonePermission,
                    screenSharingPermission: $screenSharingPermission,
                    locationPermission: $locationPermission,
                    deviceSensorPermission: $deviceSensorPermission,
                )

                SiteSettingsTimeLimitsSection(
                    domain: site.domain,
                    domainTimeTracker: browserState.domainTimeTracker,
                    timeLimitEnabled: $timeLimitEnabled,
                    timeLimitMinutes: $timeLimitMinutes,
                )
            }
            .formStyle(.grouped)
            .navigationTitle(site.domain)
            .task { await loadTimeLimit() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Reset to Defaults") {
                        showResetConfirmation = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveChanges()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 520)
        .alert("Reset to Defaults", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetToDefaults()
            }
        } message: {
            Text("Reset all settings for \(site.domain) to their default values?")
        }
    }

    private func loadTimeLimit() async {
        let tracker = browserState.domainTimeTracker
        if let limit = await tracker.limit(for: site.domain) {
            timeLimitEnabled = limit.isEnabled
            timeLimitMinutes = limit.dailyLimitSeconds / 60
        } else {
            timeLimitEnabled = false
            timeLimitMinutes = 30
        }
    }

    private func saveTimeLimit() async {
        let tracker = browserState.domainTimeTracker
        if timeLimitEnabled {
            await tracker.setLimit(for: site.domain, limitSeconds: timeLimitMinutes * 60, enabled: true)
        } else {
            // Remove or disable the limit by setting enabled to false
            await tracker.setLimit(for: site.domain, limitSeconds: timeLimitMinutes * 60, enabled: false)
        }
    }

    // MARK: - Actions

    private func saveChanges() {
        site.pageZoom = Int(pageZoom)
        site.allowJavaScript = allowJavaScript
        site.enableContentBlockers = enableContentBlockers
        site.disableAutoConsent = disableAutoConsent
        site.popUpPolicy = popUpPolicy
        site.autoPlayPolicy = autoPlayPolicy
        site.gpcHeaderOverride = gpcHeaderOverride
        site.useReaderWhenAvailable = useReaderWhenAvailable
        site.cameraPermission = cameraPermission
        site.microphonePermission = microphonePermission
        site.screenSharingPermission = screenSharingPermission
        site.locationPermission = locationPermission
        site.deviceSensorPermission = deviceSensorPermission
        // Appearance
        site.darkModeOverride = darkModeOverride
        site.pageFilterOverride = pageFilterOverride
        site.backgroundRemovalOverride = backgroundRemovalOverride
        site.contentProtectionBypass = contentProtectionBypass
        site.websiteColoringPolicy = websiteColoringPolicy
        site.pipPreference = pipPreference
        // Web behavior
        site.beforeUnloadAlertOverride = beforeUnloadAlertOverride
        site.scrollHijackingOverride = scrollHijackingOverride
        site.videoControlsOverride = videoControlsOverride
        site.videoSpeedOverride = videoSpeedOverride
        site.calmPage = calmPage

        siteSettingsManager.save(site)
        Task { await saveTimeLimit() }
        onSave()
    }

    private func resetToDefaults() {
        pageZoom = 100
        allowJavaScript = true
        enableContentBlockers = true
        disableAutoConsent = false
        popUpPolicy = .blockAndNotify
        autoPlayPolicy = .stopMediaWithSound
        gpcHeaderOverride = .useAllowlist
        useReaderWhenAvailable = false
        cameraPermission = .ask
        microphonePermission = .ask
        screenSharingPermission = .ask
        locationPermission = .ask
        deviceSensorPermission = .ask
        // Appearance
        darkModeOverride = .auto
        pageFilterOverride = .auto
        backgroundRemovalOverride = .auto
        contentProtectionBypass = nil
        websiteColoringPolicy = .useDefault
        pipPreference = .system
        // Web behavior
        beforeUnloadAlertOverride = .useDefault
        scrollHijackingOverride = .useDefault
        videoControlsOverride = .useDefault
        videoSpeedOverride = nil
        calmPage = false
        // Time limits
        timeLimitEnabled = false
        timeLimitMinutes = 30
    }
}

// MARK: - Add Domain Sheet

private struct AddDomainSheet: View {
    @Environment(SiteSettingsManager.self) private var siteSettingsManager
    @Environment(\.dismiss) private var dismiss

    let existingDomains: Set<String>
    let onAdd: (SiteSettings) -> Void

    @State private var domain = ""
    @FocusState private var isFocused: Bool

    private var normalizedDomain: String {
        domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var validationError: String? {
        let input = normalizedDomain

        if input.isEmpty {
            return nil // Don't show error for empty input
        }

        // Check for duplicate
        if existingDomains.contains(input) {
            return "Settings for this domain already exist"
        }

        // Basic domain format validation
        if input.contains(" ") {
            return "Domain cannot contain spaces"
        }

        if input.hasPrefix(".") || input.hasSuffix(".") {
            return "Domain cannot start or end with a period"
        }

        if input.hasPrefix("-") || input.hasSuffix("-") {
            return "Domain cannot start or end with a hyphen"
        }

        if input.contains("..") {
            return "Domain cannot contain consecutive periods"
        }

        // Must have at least one period (e.g., "example.com")
        if !input.contains(".") {
            return "Enter a valid domain (e.g., example.com)"
        }

        // Check for invalid characters
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        if input.unicodeScalars.contains(where: { !allowedCharacters.contains($0) }) {
            return "Domain contains invalid characters"
        }

        // Check TLD exists (at least 2 characters after last period)
        if let lastDot = input.lastIndex(of: ".") {
            let tld = input[input.index(after: lastDot)...]
            if tld.count < 2 {
                return "Invalid top-level domain"
            }
        }

        return nil
    }

    private var canAdd: Bool {
        !normalizedDomain.isEmpty && validationError == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Add Domain")
                    .font(.headline)

                Spacer()

                Button("Add") {
                    addDomain()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canAdd)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Domain")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    TextField("example.com", text: $domain)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        .onSubmit {
                            if canAdd {
                                addDomain()
                            }
                        }

                    if let error = validationError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Text("Create custom settings for a specific website. You can configure zoom, JavaScript, permissions, and other options.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .padding(20)
        }
        .frame(width: 400, height: 220)
        .onAppear {
            isFocused = true
        }
    }

    private func addDomain() {
        let settings = siteSettingsManager.settingsOrCreate(for: normalizedDomain)
        siteSettingsManager.save(settings)
        dismiss()
        onAdd(settings)
    }
}
