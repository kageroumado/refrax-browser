import SwiftUI

/// Shields in Privacy settings: the switch, the filter lists, and what the WebKit engine
/// cannot apply.
struct ShieldsSettingsSections: View {
    let highlightedItemId: String?
    @Environment(BrowserSettings.self) private var settings
    @Environment(BrowserState.self) private var browserState
    @Environment(ExtensionManager.self) private var extensionManager
    @State private var newListURL = ""

    private var shields: ShieldsStore {
        browserState.shields
    }

    var body: some View {
        @Bindable var settings = settings

        Section {
            Toggle("Block ads and trackers", isOn: $settings.enableContentBlocking)
                .highlightable(id: "privacy.shields", highlightedItemId: highlightedItemId)
            Toggle("Aggressive blocking", isOn: $settings.aggressiveContentBlocking)
                .disabled(!settings.enableContentBlocking)
                .highlightable(id: "privacy.shieldsMode", highlightedItemId: highlightedItemId)
            status
        } header: {
            Text("Shields")
        } footer: {
            Text("""
            Shields applies the same filter lists in WebKit and Chromium pages: blocking, \
            redirects, element hiding and uBlock Origin's scriptlets. Aggressive blocking also \
            blocks first-party requests a filter matches, in Chromium pages.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if extensionManager.isUBlockOriginEnabled {
            Section {
                Text("""
                uBlock Origin is on, so it hides elements and runs scriptlets in WebKit pages. \
                Shields keeps blocking requests, which uBlock Origin cannot do in WebKit.
                """)
                .font(.callout)
                Button("Turn Off uBlock Origin") {
                    Task { await extensionManager.disableUBlockOrigin() }
                }
            }
        }

        Section {
            ForEach(shields.lists) { list in
                listRow(list)
            }
            HStack {
                TextField("Filter list URL", text: $newListURL)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    addList()
                }
                .disabled(URL(string: newListURL)?.isWebURL != true)
            }
        } header: {
            Text("Filter Lists")
        } footer: {
            if let unsupported = unsupportedCount, unsupported > 0 {
                Text("\(unsupported.formatted()) filters need the Chromium engine (regular expressions, $csp, example.* hosts and other forms WebKit's rule lists cannot express).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section {
            Button("Use uBlock Origin Instead…") {
                Task { try? await extensionManager.installBundledUBlockOrigin() }
            }
            .disabled(extensionManager.isUBlockOriginEnabled)
        } footer: {
            Text("""
            Installs the uBlock Origin extension that ships with Refrax. While it runs, it handles \
            element hiding and scriptlets in WebKit pages and Shields keeps blocking requests.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var unsupportedCount: Int? {
        shields.artifacts.map { $0.manifest.webKit.counts.unsupported.values.reduce(0, +) }
    }

    private var status: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let artifacts = shields.artifacts {
                    let filters = artifacts.manifest.lists.reduce(0) { $0 + $1.stats.network + $1.stats.cosmetic }
                    Text("\(filters.formatted()) filters from \(artifacts.manifest.lists.count) lists")
                } else {
                    Text("No filter lists built yet")
                }
                if let lastUpdate = shields.lastUpdate {
                    Text("Updated \(lastUpdate.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = shields.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            if shields.isUpdating {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Update Now") {
                shields.updateNow()
            }
            .disabled(shields.isUpdating)
        }
    }

    private func listRow(_ list: FilterListSource) -> some View {
        HStack {
            Toggle(isOn: Binding(get: { list.isEnabled }, set: { shields.setListEnabled(list.id, enabled: $0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                    if let error = list.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if let count = list.ruleCount, list.isEnabled {
                        Text("\(count.formatted()) filters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if list.category == .custom {
                Button {
                    shields.removeCustomList(list.id)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove \(list.name)")
                .accessibilityLabel("Remove \(list.name)")
            }
        }
    }

    private func addList() {
        guard let url = URL(string: newListURL), url.isWebURL else { return }
        shields.addCustomList(name: url.lastPathComponent.isEmpty ? (url.host() ?? "Custom list") : url.lastPathComponent, url: url)
        newListURL = ""
    }
}
