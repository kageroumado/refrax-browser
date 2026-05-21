import SwiftUI

// MARK: - GPC Header Sites

struct GPCHeaderSitesSheet: View {
    @Environment(SiteSettingsManager.self) private var siteSettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var newDomain = ""
    @State private var newPolicy: GPCHeaderOverride = .allow
    @State private var allSiteSettings: [SiteSettings] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(allowedSites) { site in
                        GPCHeaderSiteRow(site: site)
                    }
                    .onDelete(perform: deleteAllowed)
                } header: {
                    Text("Allowed")
                }

                Section {
                    ForEach(blockedSites) { site in
                        GPCHeaderSiteRow(site: site)
                    }
                    .onDelete(perform: deleteBlocked)
                } header: {
                    Text("Blocked")
                }
            }
            .overlay {
                if allowedSites.isEmpty, blockedSites.isEmpty {
                    ContentUnavailableView {
                        Label("No GPC Overrides", systemImage: "shield")
                    } description: {
                        Text("Add a domain to explicitly allow or block the GPC header.")
                    }
                }
            }
            .navigationTitle("GPC Header Sites")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    TextField("example.com", text: $newDomain)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()

                    Picker("", selection: $newPolicy) {
                        Text(GPCHeaderOverride.allow.displayName).tag(GPCHeaderOverride.allow)
                        Text(GPCHeaderOverride.block.displayName).tag(GPCHeaderOverride.block)
                    }
                    .labelsHidden()
                    .fixedSize()

                    Button("Add") {
                        addDomain()
                    }
                    .disabled(newDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(.regularMaterial)
            }
        }
        .onAppear(perform: refreshSites)
    }

    private var allowedSites: [SiteSettings] {
        allSiteSettings.filter { $0.gpcHeaderOverride == .allow }
    }

    private var blockedSites: [SiteSettings] {
        allSiteSettings.filter { $0.gpcHeaderOverride == .block }
    }

    private func refreshSites() {
        // Query SwiftData directly to keep the allowlist editable and persistent.
        allSiteSettings = siteSettingsManager.fetchSitesWithGPCHeaderOverrides()
            .sorted { $0.domain < $1.domain }
    }

    private func addDomain() {
        let normalized = newDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }

        let settings = siteSettingsManager.settingsOrCreate(for: normalized)
        settings.gpcHeaderOverride = newPolicy
        siteSettingsManager.save(settings)

        newDomain = ""
        refreshSites()
    }

    private func deleteAllowed(at offsets: IndexSet) {
        resetOverrides(at: offsets, in: allowedSites)
    }

    private func deleteBlocked(at offsets: IndexSet) {
        resetOverrides(at: offsets, in: blockedSites)
    }

    private func resetOverrides(at offsets: IndexSet, in sites: [SiteSettings]) {
        for index in offsets {
            let site = sites[index]
            site.gpcHeaderOverride = .useAllowlist
            siteSettingsManager.save(site)
        }
        refreshSites()
    }
}

// MARK: - GPC Header Site Row

struct GPCHeaderSiteRow: View {
    let site: SiteSettings
    @Environment(SiteSettingsManager.self) private var siteSettingsManager

    var body: some View {
        HStack {
            Text(site.domain)
            Spacer()
            Picker("", selection: Binding(
                get: { site.gpcHeaderOverride },
                set: { newValue in
                    site.gpcHeaderOverride = newValue
                    siteSettingsManager.save(site)
                },
            )) {
                ForEach([GPCHeaderOverride.allow, GPCHeaderOverride.block], id: \.self) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}
