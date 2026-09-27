import AppKit
import SwiftUI

// MARK: - Engines Settings

/// Installed rendering engines: what each one is, whether it is running, and removal.
struct EnginesSettingsView: View {
    @Environment(EngineRegistry.self) private var registry
    @Environment(BrowserSettings.self) private var settings
    let highlightedItemId: String?

    @State private var pendingRemoval: EngineDescriptor?
    @State private var removalError: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Default engine", selection: $settings.defaultEngineID) {
                    ForEach(registry.descriptors, id: \.id) { descriptor in
                        Text(descriptor.displayName).tag(descriptor.id)
                    }
                    if registry.descriptor(for: settings.defaultEngineID) == nil {
                        Text("\(settings.defaultEngineID.rawValue) (not installed)").tag(settings.defaultEngineID)
                    }
                }
                .highlightable(id: "engines.default", highlightedItemId: highlightedItemId)
            } footer: {
                Text("Pages render with this engine unless their tab was moved to another one with View → Reload in… or the reload button's menu. Open pages switch the next time they load.")
            }

            Section {
                ForEach(registry.descriptors, id: \.id) { descriptor in
                    EngineRow(
                        descriptor: descriptor,
                        isRunning: registry.runningEngines.contains(descriptor.id),
                        bundleURL: registry.bundleURL(for: descriptor.id),
                        securityFloor: registry.securityFloor(blocking: descriptor.id)?.description,
                        onRemove: { pendingRemoval = descriptor },
                    )
                }
            } header: {
                Text("Installed Engines")
            } footer: {
                Text("A tab remembers the engine it was moved to. Pages whose engine is removed render with WebKit.")
            }
            .highlightable(id: "engines.installed", highlightedItemId: highlightedItemId)

            AvailableEnginesSection(distribution: registry.distribution)
                .highlightable(id: "engines.available", highlightedItemId: highlightedItemId)

            Section {
                LabeledContent("Location") {
                    Text((registry.enginesDirectory.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: registry.enginesDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([registry.enginesDirectory])
                    }
                    Button("Rescan") {
                        registry.refresh()
                    }
                }
            } header: {
                Text("Engines Folder")
            } footer: {
                Text("Refrax loads an engine only if it is signed by the same developer as Refrax.")
            }
            .highlightable(id: "engines.folder", highlightedItemId: highlightedItemId)
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Remove \(pendingRemoval?.displayName ?? "engine")?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval,
        ) { descriptor in
            Button("Remove Engine and Its Data", role: .destructive) { remove(descriptor, removingData: true) }
            Button("Remove Engine Only") { remove(descriptor, removingData: false) }
            Button("Cancel", role: .cancel) {}
        } message: { descriptor in
            Text("\(descriptor.displayName) moves to the Trash. Tabs that used it open in WebKit. Its data holds cookies and site storage from pages it rendered.")
        }
        .alert("Couldn't Remove Engine", isPresented: Binding(get: { removalError != nil }, set: { if !$0 { removalError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(removalError ?? "")
        }
    }

    private func remove(_ descriptor: EngineDescriptor, removingData: Bool) {
        do {
            try registry.uninstall(descriptor.id, removingData: removingData)
        } catch {
            removalError = error.localizedDescription
        }
    }
}

// MARK: - Engine Row

private struct EngineRow: View {
    let descriptor: EngineDescriptor
    let isRunning: Bool
    let bundleURL: URL?
    /// The release this one is below, when it may not run.
    let securityFloor: String?
    let onRemove: () -> Void

    private var isBuiltIn: Bool {
        descriptor.id == .systemWebKit
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isBuiltIn ? "safari" : "shippingbox")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(descriptor.displayName)
                        .font(.headline)
                    if securityFloor != nil {
                        Text("Update required")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.red))
                    }
                    if isRunning, !isBuiltIn {
                        Text("Running")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary))
                    }
                }
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let securityFloor {
                    Text("This release has known security problems. Its pages render with WebKit until it's updated to \(securityFloor) or later.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text(capabilitySummary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if !isBuiltIn {
                Menu {
                    if let bundleURL {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
                        }
                    }
                    Button("Remove…", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }

    private var details: String {
        // An installed release names itself (152.0.7977.82-r2); a local build shows what it renders with.
        var parts = [EngineReleaseVersion(descriptor.version) != nil ? "\(descriptor.displayName) \(descriptor.version)" : descriptor.engineVersion]
        if !descriptor.vendor.isEmpty {
            parts.append(descriptor.vendor)
        }
        parts.append(isBuiltIn ? "Built in" : descriptor.isOutOfProcess ? "Separate process" : "In Refrax's process")
        parts.append("Contract \(descriptor.contractVersion)")
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var capabilitySummary: String {
        let names = EngineCapabilities.namesByCapability
            .filter { descriptor.capabilities.contains($0.1) }
            .map(\.0)
        return names.isEmpty ? "Renders pages" : "Supports: " + names.joined(separator: ", ")
    }
}

// MARK: - Available Engines

/// Engines the catalog offers: installs, updates and their progress.
private struct AvailableEnginesSection: View {
    let distribution: EngineDistribution

    var body: some View {
        Section {
            ForEach(distribution.offers) { offer in
                OfferRow(offer: offer, state: distribution.installs[offer.id], distribution: distribution)
            }
            ForEach(pendingOnly, id: \.self) { id in
                LabeledContent(id.rawValue) {
                    RelaunchPrompt()
                }
            }
            ForEach(distribution.completed, id: \.version) { completion in
                Label(
                    completion.isUpdate
                        ? "\(completion.displayName) updated to \(completion.version)"
                        : "\(completion.displayName) \(completion.version) installed",
                    systemImage: "checkmark.circle.fill",
                )
                .foregroundStyle(.secondary)
            }
            HStack {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Check for Updates") {
                    Task { await distribution.checkForUpdates() }
                }
                .disabled(distribution.catalogState == .checking)
            }
        } header: {
            Text("Available Engines")
        } footer: {
            Text("Engines download from Refrax's release page, and install only if they carry Refrax's release signature and developer signature.")
        }
        .task {
            if distribution.catalogState == .unchecked {
                await distribution.checkForUpdates()
            }
        }
    }

    /// Engines updated in the background whose offer is gone because the catalog now matches
    /// what was downloaded, but which wait for a relaunch.
    private var pendingOnly: [EngineID] {
        let offered = Set(distribution.offers.map(\.id))
        return distribution.installs.compactMap { id, state in
            state == .pendingRelaunch && !offered.contains(id) ? id : nil
        }
        .sorted { $0.rawValue < $1.rawValue }
    }

    private var statusText: String {
        switch distribution.catalogState {
        case .unchecked, .checking:
            "Checking…"
        case let .failed(message):
            "Couldn't check: \(message)"
        case let .loaded(checkedAt):
            distribution.offers.isEmpty
                ? "Up to date · checked \(checkedAt.formatted(date: .omitted, time: .shortened))"
                : "Checked \(checkedAt.formatted(date: .omitted, time: .shortened))"
        }
    }
}

/// An update to a running engine installs at the next launch: a loaded engine can't be unloaded.
private struct RelaunchPrompt: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Takes effect after a relaunch")
                .foregroundStyle(.secondary)
            Button("Relaunch Refrax") {
                AppDelegate.relaunchAfterQuitting()
            }
        }
    }
}

private struct OfferRow: View {
    let offer: EngineDistribution.Offer
    let state: EngineDistribution.InstallState?
    let distribution: EngineDistribution

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(offer.displayName)
                    .font(.headline)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case let .failed(message) = state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            trailing
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case let .downloading(fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction)
                    .frame(width: 90)
                Button("Cancel") { distribution.cancelInstall(offer.id) }
            }
        case .verifying:
            ProgressView().controlSize(.small)
            Text("Verifying…").foregroundStyle(.secondary)
        case .installing:
            ProgressView().controlSize(.small)
            Text("Installing…").foregroundStyle(.secondary)
        case .pendingRelaunch:
            RelaunchPrompt()
        case .failed, nil:
            Button(offer.isUpdate ? "Update" : "Install") { distribution.install(offer) }
        }
    }

    private var details: String {
        let size = ByteCountFormatter.string(fromByteCount: offer.release.sizeBytes, countStyle: .file)
        if let installed = offer.installedVersion {
            return "\(installed) → \(offer.release.version) · \(size)"
        }
        return "\(offer.release.version) · \(size)"
    }
}
